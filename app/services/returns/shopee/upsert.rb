# frozen_string_literal: true

module Returns
  module Shopee
    class Upsert
      def self.call!(shop:, raw_return:)
        new(shop:, raw_return:).call!
      end

      def initialize(shop:, raw_return:)
        @shop = shop
        @raw = raw_return
      end

      def call!
        raise ArgumentError, "shop required" if @shop.nil?
        raise ArgumentError, "raw_return required" if @raw.nil?

        external_return_id = @raw.fetch("external_return_id").to_s
        external_order_id = @raw.fetch("external_order_id").to_s

        order = find_order_for_return!(external_order_id)

        shipment = nil
        sku_codes = Array(@raw["lines"]).map { |line| line["sku_code_snapshot"].to_s.strip }.reject(&:blank?).uniq

        ReturnShipment.transaction do
          shipment = ReturnShipment.find_or_initialize_by(
            channel: "shopee",
            shop_id: @shop.id,
            external_return_id: external_return_id
          )

          shipment.assign_attributes(
            order: order,
            external_order_id: external_order_id,
            tracking_number: @raw["tracking_number"],
            status_marketplace: @raw["status_marketplace"],
            status_store: shipment.status_store.presence || "pending_scan",
            requested_at: @raw["requested_at"],
            return_carrier_method: @raw["return_carrier_method"],
            return_delivery_status: @raw["return_delivery_status"],
            returned_delivered_at: @raw["returned_delivered_at"],
            buyer_username: @raw["buyer_username"],
            raw_payload: @raw["raw_payload"] || {},
            meta: build_shipment_meta(order: order, external_order_id: external_order_id),
            last_seen_at_external: Time.current
          )

          shipment.save!

          upsert_lines!(shipment: shipment, order: order, raw_lines: Array(@raw["lines"]))

          Inventory::RemapSkuReferences.call!(
            shop: @shop,
            channel: "shopee",
            external_skus: sku_codes
          )

          shipment.reload.refresh_status_store!
        end

        Rails.logger.info(
          {
            event: "returns.shopee.upsert.done",
            shop_id: @shop.id,
            shop_code: @shop.shop_code,
            return_shipment_id: shipment.id,
            external_return_id: shipment.external_return_id,
            external_order_id: shipment.external_order_id,
            order_id: shipment.order_id,
            line_count: shipment.return_shipment_lines.count,
            status_marketplace: shipment.status_marketplace,
            status_store: shipment.status_store
          }.to_json
        )

        shipment
      end

      private

      def find_order_for_return!(external_order_id)
        exact = Order.find_by(
          channel: "shopee",
          shop_id: @shop.id,
          external_order_id: external_order_id
        )
        return exact if exact.present?

        cross_shop_matches = Order.where(
          channel: "shopee",
          external_order_id: external_order_id
        ).order(:shop_id, :id).to_a

        if cross_shop_matches.size == 1
          matched = cross_shop_matches.first

          Rails.logger.warn(
            {
              event: "returns.shopee.upsert.order_cross_shop_match",
              return_shop_id: @shop.id,
              return_shop_code: @shop.shop_code,
              matched_order_id: matched.id,
              matched_order_shop_id: matched.shop_id,
              external_order_id: external_order_id
            }.to_json
          )

          return matched
        end

        if cross_shop_matches.size > 1
          Rails.logger.error(
            {
              event: "returns.shopee.upsert.order_ambiguous_cross_shop_match",
              return_shop_id: @shop.id,
              return_shop_code: @shop.shop_code,
              external_order_id: external_order_id,
              matched_order_ids: cross_shop_matches.map(&:id),
              matched_shop_ids: cross_shop_matches.map(&:shop_id).uniq
            }.to_json
          )

          raise ArgumentError, "ambiguous shopee order match for external_order_id=#{external_order_id}"
        end

        Rails.logger.warn(
          {
            event: "returns.shopee.upsert.order_not_found",
            return_shop_id: @shop.id,
            return_shop_code: @shop.shop_code,
            external_order_id: external_order_id
          }.to_json
        )

        nil
      end

      def build_shipment_meta(order:, external_order_id:)
        ({}).merge(@raw["meta"].is_a?(Hash) ? @raw["meta"] : {})
            .merge(
              "source" => "shopee_return_import",
              "status_marketplace_raw" => @raw["status_marketplace_raw"],
              "order_match_status" => order_match_status(order, external_order_id),
              "matched_order_shop_id" => order&.shop_id
            )
      end

      def order_match_status(order, external_order_id)
        return "missing" if order.nil?
        return "exact_shop" if order.shop_id == @shop.id

        other_matches = Order.where(
          channel: "shopee",
          external_order_id: external_order_id
        ).where.not(id: order.id)

        return "cross_shop_fallback" if other_matches.none?

        "cross_shop_selected"
      end

      def upsert_lines!(shipment:, order:, raw_lines:)
        now = Time.current
        sku_codes = raw_lines.map { |r| r["sku_code_snapshot"].to_s.strip }.reject(&:blank?).uniq
        skus_by_code = Sku.where(code: sku_codes).index_by(&:code)

        existing_lines = shipment.return_shipment_lines.index_by { |line| line.external_line_id.to_s }

        rows = raw_lines.map do |line|
          sku_code = line["sku_code_snapshot"].to_s.strip
          sku = skus_by_code[sku_code]
          existing = existing_lines[line["external_line_id"].to_s]
          requested_qty = [ line["qty_returned"].to_i, 1 ].max

          order_line = Returns::ResolveOrderLine.call(
            order: order,
            existing_order_line: existing&.order_line,
            sku_code: sku_code,
            requested_qty: requested_qty
          )

          log_unmapped_line!(
            shipment: shipment,
            sku_code: sku_code,
            requested_qty: requested_qty,
            sku: sku,
            order_line: order_line
          )

          {
            return_shipment_id: shipment.id,
            order_line_id: order_line&.id,
            sku_id: sku&.id,
            external_line_id: line["external_line_id"].to_s.presence,
            sku_code_snapshot: sku_code,
            qty_returned: requested_qty,
            raw_payload: line["raw_payload"] || {},
            created_at: now,
            updated_at: now
          }
        end

        ReturnShipmentLine.upsert_all(
          rows,
          unique_by: :uniq_return_shipment_lines_external_line,
          record_timestamps: false,
          update_only: %i[
            order_line_id
            sku_id
            sku_code_snapshot
            qty_returned
            raw_payload
            updated_at
          ]
        )
      end

      def log_unmapped_line!(shipment:, sku_code:, requested_qty:, sku:, order_line:)
        return if sku.present? && order_line.present?

        Rails.logger.warn(
          {
            event: "returns.shopee.upsert.line_unmapped",
            return_shipment_id: shipment.id,
            external_return_id: shipment.external_return_id,
            external_order_id: shipment.external_order_id,
            shop_id: shipment.shop_id,
            sku_code: sku_code,
            requested_qty: requested_qty,
            sku_found: sku.present?,
            order_line_found: order_line.present?
          }.to_json
        )
      end
    end
  end
end

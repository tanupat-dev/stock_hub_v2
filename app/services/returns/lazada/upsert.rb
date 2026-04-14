# frozen_string_literal: true

module Returns
  module Lazada
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

        order = Order.find_by(
          channel: "lazada",
          shop_id: @shop.id,
          external_order_id: external_order_id
        )

        shipment = nil
        external_skus = Array(@raw["lines"]).map { |line| line["external_sku"].to_s.strip }.reject(&:blank?).uniq

        ReturnShipment.transaction do
          shipment = ReturnShipment.find_or_initialize_by(
            channel: "lazada",
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
            meta: (shipment.meta || {}).merge(
              "source" => "lazada_reverse_poll",
              "status_marketplace_raw" => @raw["status_marketplace_raw"]
            ),
            last_seen_at_external: Time.current
          )

          shipment.save!

          upsert_lines!(shipment: shipment, order: order, raw_lines: Array(@raw["lines"]))

          Inventory::RemapSkuReferences.call!(
            shop: @shop,
            channel: "lazada",
            external_skus: external_skus
          )

          shipment.reload.refresh_status_store!
        end

        Rails.logger.info(
          {
            event: "returns.lazada.upsert.done",
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

      def upsert_lines!(shipment:, order:, raw_lines:)
        now = Time.current

        external_skus = raw_lines.map { |r| r["external_sku"].to_s.strip }.reject(&:blank?).uniq

        mappings =
          if external_skus.any?
            SkuMapping.where(channel: "lazada", shop_id: @shop.id, external_sku: external_skus).includes(:sku).index_by(&:external_sku)
          else
            {}
          end

        skus_by_code =
          if external_skus.any?
            Sku.where(code: external_skus).index_by(&:code)
          else
            {}
          end

        existing_lines = shipment.return_shipment_lines.index_by { |line| line.external_line_id.to_s }

        rows = raw_lines.map do |line|
          external_sku = line["external_sku"].to_s.strip
          mapping = mappings[external_sku]
          sku = mapping&.sku || skus_by_code[external_sku]
          existing = existing_lines[line["external_line_id"].to_s]
          requested_qty = [ line["qty_returned"].to_i, 1 ].max

          order_line = Returns::ResolveOrderLine.call(
            order: order,
            existing_order_line: existing&.order_line,
            sku_code: sku&.code || external_sku,
            requested_qty: requested_qty
          )

          log_unmapped_line!(
            shipment: shipment,
            external_sku: external_sku,
            sku: sku,
            order_line: order_line,
            requested_qty: requested_qty
          )

          {
            return_shipment_id: shipment.id,
            order_line_id: order_line&.id,
            sku_id: sku&.id,
            external_line_id: line["external_line_id"].to_s.presence,
            sku_code_snapshot: sku&.code.to_s.presence || external_sku,
            qty_returned: requested_qty,
            raw_payload: (line["raw_payload"] || {}).merge("external_sku" => external_sku),
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

      def log_unmapped_line!(shipment:, external_sku:, sku:, order_line:, requested_qty:)
        return if sku.present? && order_line.present?

        Rails.logger.warn(
          {
            event: "returns.lazada.upsert.line_unmapped",
            return_shipment_id: shipment.id,
            external_return_id: shipment.external_return_id,
            external_order_id: shipment.external_order_id,
            shop_id: shipment.shop_id,
            external_sku: external_sku,
            requested_qty: requested_qty,
            sku_found: sku.present?,
            order_line_found: order_line.present?
          }.to_json
        )
      end
    end
  end
end

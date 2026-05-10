# frozen_string_literal: true

module Returns
  module Shopee
    class CreateFromFailedDelivery
      SOURCE = "shopee_failed_delivery_import"

      def self.call!(shop:, raw_failed_delivery:)
        new(shop:, raw_failed_delivery:).call!
      end

      def initialize(shop:, raw_failed_delivery:)
        @shop = shop
        @raw = raw_failed_delivery || {}
      end

      def call!
        raise ArgumentError, "shop required" if @shop.nil?
        raise ArgumentError, "shop #{@shop.id} is not shopee" unless @shop.channel == "shopee"

        external_order_id = @raw.fetch("external_order_id").to_s.strip
        raise ArgumentError, "external_order_id required" if external_order_id.blank?

        order = find_order!(external_order_id)
        raise ArgumentError, "order #{external_order_id} has no committed lines" unless committed_lines?(order)

        shipment = nil

        ReturnShipment.transaction do
          shipment = existing_shipment(order, external_order_id)

          if shipment.present?
            annotate_existing_shipment!(shipment, order, external_order_id)
          else
            shipment = create_shipment!(order, external_order_id)
          end

          upsert_lines!(shipment, order)
          shipment.reload.refresh_status_store!
        end

        Rails.logger.info(
          {
            event: "returns.shopee.failed_delivery.done",
            shop_id: @shop.id,
            order_id: shipment.order_id,
            external_order_id: shipment.external_order_id,
            return_shipment_id: shipment.id,
            external_return_id: shipment.external_return_id,
            tracking_number: shipment.tracking_number,
            source: shipment.meta&.dig("source"),
            failed_delivery_import: shipment.meta&.dig("failed_delivery_import"),
            failed_delivery_status: shipment.meta&.dig("failed_delivery_status"),
            line_count: shipment.return_shipment_lines.count,
            status_store: shipment.status_store
          }.to_json
        )

        shipment
      end

      private

      def find_order!(external_order_id)
        exact = Order.find_by(
          channel: "shopee",
          shop_id: @shop.id,
          external_order_id: external_order_id
        )

        return exact if exact.present?

        matches =
          Order
            .where(channel: "shopee", external_order_id: external_order_id)
            .order(:shop_id, :id)
            .to_a

        return matches.first if matches.size == 1

        if matches.size > 1
          raise ArgumentError, "ambiguous shopee order match for external_order_id=#{external_order_id}"
        end

        raise ActiveRecord::RecordNotFound, "shopee order not found external_order_id=#{external_order_id}"
      end

      def existing_shipment(order, external_order_id)
        ReturnShipment
          .where(order_id: order.id)
          .order(:id)
          .first ||
          ReturnShipment
            .where(
              channel: "shopee",
              shop_id: order.shop_id,
              external_return_id: external_return_id(external_order_id)
            )
            .order(:id)
            .first
      end

      def create_shipment!(order, external_order_id)
        ReturnShipment.create!(
          channel: "shopee",
          shop_id: order.shop_id,
          order: order,
          external_order_id: external_order_id,
          external_return_id: external_return_id(external_order_id),
          tracking_number: @raw["tracking_number"],
          status_marketplace: "failed_delivery",
          status_store: "pending_scan",
          requested_at: @raw["shipped_at"] || Time.current,
          return_carrier_method: carrier_text,
          return_delivery_status: @raw["failed_delivery_status"],
          buyer_username: @raw["buyer_username"],
          raw_payload: build_raw_payload(external_order_id),
          meta: build_meta(existing_source: nil, external_order_id: external_order_id, order: order),
          last_seen_at_external: Time.current
        )
      end

      def annotate_existing_shipment!(shipment, order, external_order_id)
        existing_source = shipment.meta&.dig("source")

        next_meta =
          (shipment.meta || {})
            .merge(build_meta(existing_source: existing_source, external_order_id: external_order_id, order: order))
            .compact

        next_raw_payload =
          (shipment.raw_payload || {})
            .merge(
              "failed_delivery_import" => build_raw_payload(external_order_id)
            )
            .compact

        attrs = {
          tracking_number: shipment.tracking_number.presence || @raw["tracking_number"],
          return_carrier_method: shipment.return_carrier_method.presence || carrier_text,
          return_delivery_status: @raw["failed_delivery_status"].presence || shipment.return_delivery_status,
          buyer_username: shipment.buyer_username.presence || @raw["buyer_username"],
          raw_payload: next_raw_payload,
          meta: next_meta,
          last_seen_at_external: Time.current
        }

        if shipment.external_return_id.blank?
          attrs[:external_return_id] = external_return_id(external_order_id)
        end

        if shipment.status_marketplace.to_s == "CANCELLED" || shipment.status_marketplace.blank?
          attrs[:status_marketplace] = "failed_delivery"
        end

        shipment.update!(attrs)
      end

      def external_return_id(external_order_id)
        "shopee_failed_delivery:#{external_order_id}"
      end

      def committed_lines?(order)
        order.order_lines.any? do |line|
          InventoryAction.where(order_line_id: line.id, action_type: "commit").exists?
        end
      end

      def committed?(line)
        InventoryAction.where(order_line_id: line.id, action_type: "commit").exists?
      end

      def upsert_lines!(shipment, order)
        now = Time.current
        raw_lines = Array(@raw["lines"])

        existing_order_line_ids =
          shipment
            .return_shipment_lines
            .pluck(:order_line_id)
            .compact
            .to_set

        rows = raw_lines.map.with_index do |line, index|
          sku_code = line["sku_code_snapshot"].to_s.strip
          requested_qty = [ line["qty_returned"].to_i, 1 ].max

          order_line =
            Returns::ResolveOrderLine.call(
              order: order,
              existing_order_line: nil,
              sku_code: sku_code,
              requested_qty: requested_qty
            )

          next if order_line.present? && existing_order_line_ids.include?(order_line.id)
          next if order_line.present? && !committed?(order_line)

          sku = order_line&.sku || Sku.find_by(code: sku_code)

          {
            return_shipment_id: shipment.id,
            order_line_id: order_line&.id,
            sku_id: sku&.id,
            external_line_id: "#{shipment.external_return_id.presence || external_return_id(order.external_order_id)}:#{sku_code.presence || index + 1}",
            sku_code_snapshot: sku_code,
            qty_returned: requested_qty,
            raw_payload: line["raw_payload"] || {},
            created_at: now,
            updated_at: now
          }
        end.compact

        return if rows.blank?

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

      def build_raw_payload(external_order_id)
        {
          "source" => SOURCE,
          "external_order_id" => external_order_id,
          "tracking_number" => @raw["tracking_number"],
          "failed_delivery_status" => @raw["failed_delivery_status"],
          "order_status_raw" => @raw["order_status_raw"],
          "rows" => @raw["rows"]
        }.compact
      end

      def build_meta(existing_source:, external_order_id:, order:)
        {
          "source" => existing_source.presence || SOURCE,
          "original_source" => existing_source,
          "failed_delivery_import" => true,
          "failed_delivery_source" => SOURCE,
          "failed_delivery_status" => @raw["failed_delivery_status"],
          "failed_delivery_tracking_number" => @raw["tracking_number"],
          "failed_delivery_imported_at" => Time.current.iso8601,
          "order_status_raw" => @raw["order_status_raw"],
          "external_order_id" => external_order_id,
          "matched_order_shop_id" => order.shop_id
        }.compact
      end

      def carrier_text
        @raw["shipping_option"].presence || @raw["shipping_method"]
      end
    end
  end
end

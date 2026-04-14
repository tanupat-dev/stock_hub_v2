# frozen_string_literal: true

module Marketplace
  module Tiktok
    class UpsertReturnShipments
      def self.call!(shop:, rows:)
        new(shop:, rows:).call!
      end

      def initialize(shop:, rows:)
        @shop = shop
        @rows = rows
      end

      def call!
        return 0 if @rows.blank?

        upserted = 0
        skipped_missing_order = 0
        skipped_non_return = 0

        external_order_ids = @rows.map { |r| r["order_id"].to_s.presence }.compact.uniq

        orders_by_external_id =
          if external_order_ids.any?
            Order.where(
              channel: "tiktok",
              shop_id: @shop.id,
              external_order_id: external_order_ids
            ).index_by(&:external_order_id)
          else
            {}
          end

        @rows.each do |r|
          external_order_id = r["order_id"].to_s
          external_return_id = r["return_id"].to_s
          tracking_number = r["return_tracking_number"].to_s

          order = orders_by_external_id[external_order_id]

          if order.nil?
            skipped_missing_order += 1
            log_info(
              event: "marketplace.tiktok.returns.upsert_skip",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              external_order_id: external_order_id,
              external_return_id: external_return_id,
              tracking_number: tracking_number,
              skip_reason: "order_not_found"
            )
            next
          end

          records = fetch_records_safely(external_return_id)

          transformed = ::Returns::Tiktok::Transformer.call(
            raw_return: r,
            records: records
          )

          unless transformed["is_return"]
            skipped_non_return += 1
            log_info(
              event: "marketplace.tiktok.returns.upsert_skip",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              external_order_id: external_order_id,
              external_return_id: external_return_id,
              tracking_number: tracking_number,
              skip_reason: "non_physical_return",
              return_type: r["return_type"],
              return_status: r["return_status"]
            )
            next
          end

          shipment = nil
          external_skus = Array(transformed["lines"]).map { |line| line["external_sku"].to_s.strip }.reject(&:blank?).uniq

          ReturnShipment.transaction do
            shipment = ReturnShipment.find_or_initialize_by(
              channel: "tiktok",
              shop_id: @shop.id,
              external_return_id: transformed["external_return_id"]
            )

            shipment.assign_attributes(
              order: order,
              external_order_id: transformed["external_order_id"],
              tracking_number: transformed["tracking_number"],
              status_marketplace: transformed["status_marketplace"],
              status_store: shipment.status_store.presence || "pending_scan",
              requested_at: transformed["requested_at"],
              return_carrier_method: transformed["return_carrier_method"],
              return_delivery_status: transformed["return_delivery_status"],
              returned_delivered_at: preserve_returned_delivered_at(
                existing_value: shipment.returned_delivered_at,
                new_value: transformed["returned_delivered_at"]
              ),
              buyer_username: transformed["buyer_username"],
              raw_payload: transformed["raw_payload"] || {},
              meta: build_meta(
                existing_meta: shipment.meta,
                transformed: transformed,
                records: records
              ),
              last_seen_at_external: Time.current
            )

            shipment.save!
            upsert_lines!(shipment: shipment, order: order, raw_lines: Array(transformed["lines"]))

            ::Inventory::RemapSkuReferences.call!(
              shop: @shop,
              channel: "tiktok",
              external_skus: external_skus
            )

            shipment.reload.refresh_status_store!
          end

          upserted += 1
        end

        log_info(
          event: "marketplace.tiktok.returns.upsert_done",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          rows: @rows.size,
          upserted: upserted,
          skipped_missing_order: skipped_missing_order,
          skipped_non_return: skipped_non_return
        )

        upserted
      end

      private

      def fetch_records_safely(external_return_id)
        return {} if external_return_id.blank?

        Marketplace::Tiktok::Returns::GetRecords.call!(
          shop: @shop,
          return_id: external_return_id
        )
      rescue => e
        Rails.logger.warn(
          {
            event: "marketplace.tiktok.returns.records_fetch_failed",
            shop_id: @shop.id,
            shop_code: @shop.shop_code,
            external_return_id: external_return_id,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )

        {}
      end

      def preserve_returned_delivered_at(existing_value:, new_value:)
        new_value.presence || existing_value
      end

      def build_meta(existing_meta:, transformed:, records:)
        (existing_meta || {}).merge(
          "source" => "tiktok_return_poll",
          "status_marketplace_raw" => transformed["status_marketplace_raw"],
          "records_fetched" => Array(records["records"]).any?,
          "is_return" => transformed["is_return"]
        )
      end

      def upsert_lines!(shipment:, order:, raw_lines:)
        return if raw_lines.blank?

        now = Time.current

        external_skus = raw_lines.map { |line| line["external_sku"].to_s.strip }.reject(&:blank?).uniq

        mappings =
          if external_skus.any?
            SkuMapping.where(
              channel: "tiktok",
              shop_id: @shop.id,
              external_sku: external_skus
            ).includes(:sku).index_by(&:external_sku)
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
          external_line_id = line["external_line_id"].to_s.presence
          external_sku = line["external_sku"].to_s.strip
          mapping = mappings[external_sku]
          sku = mapping&.sku || skus_by_code[external_sku]
          existing = existing_lines[external_line_id.to_s]
          requested_qty = [ line["qty_returned"].to_i, 1 ].max

          order_line = ::Returns::ResolveOrderLine.call(
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
            external_line_id: external_line_id,
            sku_code_snapshot: sku&.code.to_s.presence || external_sku,
            qty_returned: requested_qty,
            raw_payload: (line["raw_payload"] || {}).merge("external_sku" => external_sku),
            created_at: now,
            updated_at: now
          }
        end

        return if rows.blank?

        rows_with_external_line_id = rows.select { |row| row[:external_line_id].present? }
        rows_without_external_line_id = rows.select { |row| row[:external_line_id].blank? }

        if rows_with_external_line_id.any?
          ReturnShipmentLine.upsert_all(
            rows_with_external_line_id,
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

        rows_without_external_line_id.each do |attrs|
          shipment.return_shipment_lines.create!(attrs.except(:return_shipment_id))
        end
      end

      def log_unmapped_line!(shipment:, external_sku:, sku:, order_line:, requested_qty:)
        return if sku.present? && order_line.present?

        Rails.logger.warn(
          {
            event: "marketplace.tiktok.returns.line_unmapped",
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

      def log_info(payload)
        Rails.logger.info(payload.to_json)
      end
    end
  end
end

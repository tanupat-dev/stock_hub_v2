# frozen_string_literal: true

module Orders
  module Shopee
    class UpsertLines
      def self.call!(order:, raw_order:)
        new(order, raw_order).call!
      end

      def initialize(order, raw_order)
        @order = order
        @raw = raw_order
      end

      def call!
        items = Array(@raw["line_items"])
        return 0 if items.blank?

        now = Time.current
        sku_codes = items.map { |li| li["sku_reference"].to_s.strip }.reject(&:blank?).uniq
        skus_by_code = Sku.where(code: sku_codes).index_by(&:code)

        rows = items.map.with_index do |li, index|
          sku_code = li["sku_reference"].to_s.strip
          sku = skus_by_code[sku_code]

          base_external_line_id =
            li["id"].presence&.to_s ||
            "#{@order.external_order_id}:#{sku_code}"

          external_line_id = deduped_external_line_id(
            base_external_line_id,
            index
          )

          {
            order_id: @order.id,
            external_line_id: external_line_id,
            external_sku: sku_code.presence,
            sku_id: sku&.id,
            quantity: li["quantity"].to_i.clamp(1, 1_000_000),
            status: li["display_status"].to_s.presence || @raw["status"].to_s,
            idempotency_key: "shopee:shop:#{@order.shop_id}:order:#{@order.external_order_id}:line:#{external_line_id}",
            raw_payload: li,
            created_at: now,
            updated_at: now
          }
        end

        OrderLine.upsert_all(
          rows,
          unique_by: :index_order_lines_on_idempotency_key,
          record_timestamps: false,
          update_only: %i[
            external_line_id external_sku sku_id quantity status raw_payload updated_at
          ]
        )

        rows.size
      end

      private

      def deduped_external_line_id(base_external_line_id, index)
        "#{base_external_line_id}:row#{index + 1}"
      end
    end
  end
end

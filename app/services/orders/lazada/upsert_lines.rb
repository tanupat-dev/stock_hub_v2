# frozen_string_literal: true

module Orders
  module Lazada
    class UpsertLines
      def self.call!(shop:, order:, raw_order:)
        new(shop, order, raw_order).call!
      end

      def initialize(shop, order, raw_order)
        @shop = shop
        @order = order
        @raw = raw_order
      end

      def call!
        items = Array(@raw["line_items"])
        return 0 if items.blank?

        now = Time.current

        external_skus = items.map { |li| li["seller_sku"].to_s.strip }.reject(&:blank?).uniq

        mappings =
          if external_skus.any?
            SkuMapping.includes(:sku)
                      .where(channel: "lazada", shop_id: @shop.id, external_sku: external_skus)
                      .index_by(&:external_sku)
          else
            {}
          end

        fallback_skus_by_code =
          if external_skus.any?
            Sku.where(code: external_skus).index_by(&:code)
          else
            {}
          end

        rows =
          items.map do |li|
            external_line_id = li["id"].presence&.to_s
            seller_sku = li["seller_sku"].to_s.strip

            mapped_sku = mappings[seller_sku]&.sku
            fallback_sku = mapped_sku.present? ? nil : fallback_skus_by_code[seller_sku]
            sku = mapped_sku || fallback_sku
            sku_id = sku&.id

            idem = "lazada:shop:#{@shop.id}:order:#{@order.external_order_id}:line:#{external_line_id || seller_sku}"

            {
              order_id: @order.id,
              external_line_id: external_line_id,
              external_sku: seller_sku.presence,
              sku_id: sku_id,
              quantity: (li["quantity"].presence || 1).to_i.clamp(1, 1_000_000),
              status: (li["display_status"].presence || @raw["status"]).to_s,
              idempotency_key: idem,
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
    end
  end
end

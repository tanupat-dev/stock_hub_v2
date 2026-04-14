# frozen_string_literal: true

module Orders
  module Tiktok
    class UpsertLines
      def self.call!(order:, shop:, raw_order:)
        new(order:, shop:, raw_order:).call!
      end

      def initialize(order:, shop:, raw_order:)
        @order = order
        @shop = shop
        @raw = raw_order || {}
      end

      def call!
        items = Array(@raw["line_items"])
        return if items.blank?

        now = Time.current

        external_skus = items.map { |li| li["seller_sku"].to_s.strip }.reject(&:blank?).uniq

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

        rows = items.map do |li|
          external_line_id = li["id"].to_s.presence

          raw_sku = li["seller_sku"].to_s
          external_sku = raw_sku.strip

          mapping = mappings[external_sku]

          # ===== SKU RESOLUTION =====
          sku =
            mapping&.sku ||
            find_sku_exact(external_sku)

          # ===== AUTO CREATE MAPPING (SAFE) =====
          if mapping.blank? && sku.present? && external_sku.present?
            begin
              mapping = SkuMapping.find_or_create_by!(
                channel: "tiktok",
                shop_id: @shop.id,
                external_sku: external_sku
              ) do |m|
                m.sku_id = sku.id
              end
            rescue ActiveRecord::RecordNotUnique
              # race condition safe ignore
            end
          end

          # ===== QUANTITY FIX (CRITICAL) =====
          quantity = li["quantity"].to_i
          quantity = 1 if quantity <= 0

          idem_key = build_idempotency_key(external_line_id, external_sku)

          {
            order_id: @order.id,
            external_line_id: external_line_id,
            external_sku: external_sku,
            sku_id: sku&.id,
            quantity: quantity,
            status: @order.status,
            idempotency_key: idem_key,
            raw_payload: li,
            created_at: now,
            updated_at: now
          }
        end

        return if rows.blank?

        OrderLine.upsert_all(
          rows,
          unique_by: :index_order_lines_on_idempotency_key,
          record_timestamps: false,
          update_only: %i[
            sku_id
            external_sku
            quantity
            status
            raw_payload
            updated_at
          ]
        )
      end

      private

      # ===== SKU LOOKUP =====

      def find_sku_exact(code)
        return nil if code.blank?
        Sku.find_by(code: code)
      end

      # ===== IDEMPOTENCY =====

      def build_idempotency_key(external_line_id, external_sku)
        base = external_line_id.presence || external_sku.presence || SecureRandom.uuid

        "tiktok:shop:#{@shop.id}:order:#{@order.external_order_id}:line:#{base}"
      end
    end
  end
end

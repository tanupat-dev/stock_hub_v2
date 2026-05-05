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
        return 0 if items.blank?

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

        rows = []

        items.each do |li|
          external_line_id = li["id"].to_s.presence

          raw_sku = li["seller_sku"].to_s
          external_sku = raw_sku.strip
          next if external_sku.blank?

          mapping = mappings[external_sku]

          sku =
            mapping&.sku ||
            find_sku_exact(external_sku)

          if mapping.blank? && sku.present?
            mapping = find_or_create_mapping!(external_sku, sku)
            mappings[external_sku] = mapping if mapping.present?
          end

          quantity = li["quantity"].to_i
          quantity = 1 if quantity <= 0

          existing_line = existing_line_for(
            external_line_id: external_line_id,
            external_sku: external_sku
          )

          idempotency_key =
            existing_line&.idempotency_key.presence ||
            build_canonical_idempotency_key(external_line_id, external_sku)

          rows << {
            order_id: @order.id,
            external_line_id: external_line_id,
            external_sku: external_sku,
            sku_id: sku&.id,
            quantity: quantity,
            status: li["display_status"].to_s.presence || @order.status,
            idempotency_key: idempotency_key,
            raw_payload: li,
            created_at: now,
            updated_at: now
          }
        end

        return 0 if rows.blank?

        OrderLine.upsert_all(
          rows,
          unique_by: :index_order_lines_on_idempotency_key,
          record_timestamps: false,
          update_only: %i[
            external_line_id
            external_sku
            sku_id
            quantity
            status
            raw_payload
            updated_at
          ]
        )

        rows.size
      end

      private

      def existing_line_for(external_line_id:, external_sku:)
        if external_line_id.present?
          line =
            OrderLine.find_by(
              order_id: @order.id,
              external_line_id: external_line_id
            )

          return line if line.present?
        end

        return nil if external_sku.blank?

        OrderLine
          .where(order_id: @order.id, external_sku: external_sku)
          .order(:id)
          .first
      end

      def find_sku_exact(code)
        return nil if code.blank?

        Sku.find_by(code: code)
      end

      def find_or_create_mapping!(external_sku, sku)
        SkuMapping.find_or_create_by!(
          channel: "tiktok",
          shop_id: @shop.id,
          external_sku: external_sku
        ) do |mapping|
          mapping.sku_id = sku.id
        end
      rescue ActiveRecord::RecordNotUnique
        SkuMapping.find_by(
          channel: "tiktok",
          shop_id: @shop.id,
          external_sku: external_sku
        )
      end

      def build_canonical_idempotency_key(external_line_id, external_sku)
        base = external_line_id.presence || external_sku.presence || SecureRandom.uuid

        # Important:
        # keep this aligned with Orders::UpsertFromSearchRows.
        # Old detail keys had "tiktok:shop:<shop_id>:order:..."
        # We preserve old keys only when an existing line is found.
        "tiktok:order:#{@order.external_order_id}:line:#{base}"
      end
    end
  end
end

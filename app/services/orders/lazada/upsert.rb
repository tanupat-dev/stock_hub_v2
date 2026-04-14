# frozen_string_literal: true

module Orders
  module Lazada
    class Upsert
      def self.call!(shop:, raw_order:)
        new(shop, raw_order).call!
      end

      def initialize(shop, raw_order)
        @shop = shop
        @raw = raw_order
        raise ArgumentError, "shop required" if @shop.nil?
        raise ArgumentError, "raw_order required" if @raw.nil?
      end

      def call!
        external_order_id = @raw.fetch("id").to_s
        status = @raw.fetch("status").to_s

        order = nil
        previous_status = nil

        Order.transaction do
          existing = Order.find_by(
            channel: "lazada",
            shop_id: @shop.id,
            external_order_id: external_order_id
          )

          previous_status = existing&.status

          Order.upsert(
            {
              channel: "lazada",
              shop_id: @shop.id,
              external_order_id: external_order_id,
              status: status,
              buyer_name: @raw["buyer_name"],
              province: @raw["province"],
              buyer_note: @raw["buyer_note"],
              updated_time_external: @raw["update_time"],
              updated_at_external: (@raw["update_time"].present? ? Time.at(@raw["update_time"].to_i) : nil),
              raw_payload: @raw,
              created_at: Time.current,
              updated_at: Time.current
            },
            unique_by: :uniq_orders_channel_shop_external
          )

          order =
            Order.find_by!(
              channel: "lazada",
              shop_id: @shop.id,
              external_order_id: external_order_id
            )

          Orders::Lazada::UpsertLines.call!(shop: @shop, order: order, raw_order: @raw)

          Inventory::RemapSkuReferences.call!(
            shop: @shop,
            channel: "lazada",
            external_skus: extracted_external_skus
          )

          Orders::Lazada::ApplyPolicy.call!(
            order: order,
            raw_order: @raw,
            previous_status: previous_status
          )
        end

        order
      end

      private

      def extracted_external_skus
        Array(@raw["line_items"])
          .map { |li| li["seller_sku"].to_s.strip }
          .reject(&:blank?)
          .uniq
      end
    end
  end
end

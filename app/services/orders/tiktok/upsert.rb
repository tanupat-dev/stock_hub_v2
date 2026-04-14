# frozen_string_literal: true

module Orders
  module Tiktok
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
            channel: "tiktok",
            shop_id: @shop.id,
            external_order_id: external_order_id
          )

          previous_status = existing&.status

          Order.upsert(
            {
              channel: "tiktok",
              shop_id: @shop.id,
              external_order_id: external_order_id,
              status: status,
              buyer_name: @raw.dig("recipient_address", "name"),
              province: @raw.dig("recipient_address", "district_info")&.first&.dig("address_name"),
              buyer_note: @raw["buyer_message"],
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
              channel: "tiktok",
              shop_id: @shop.id,
              external_order_id: external_order_id
            )

          Orders::Tiktok::UpsertLines.call!(shop: @shop, order: order, raw_order: @raw)

          Orders::Tiktok::ApplyPolicy.call!(
            order: order,
            raw_order: @raw,
            previous_status: previous_status
          )
        end

        order
      end
    end
  end
end

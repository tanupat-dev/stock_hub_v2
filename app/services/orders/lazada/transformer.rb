# frozen_string_literal: true

require "time"

module Orders
  module Lazada
    class Transformer
      def self.call(orders:, items:)
        items_by_order = Array(items).index_by { |i| i["order_id"].to_s }

        Array(orders).map do |o|
          bucket = items_by_order[o["order_id"].to_s] || {}
          order_items = Array(bucket["order_items"])

          shipping = o["address_shipping"] || {}
          billing = o["address_billing"] || {}

          {
            "id" => o["order_id"].to_s,
            "status" => derive_status(order: o, items: order_items),
            "update_time" => parse_time_to_i(o["updated_at"]),
            "created_at" => o["created_at"].to_s.presence,
            "updated_at" => o["updated_at"].to_s.presence,

            "buyer_name" => build_buyer_name(o),
            "province" => extract_province(o),
            "buyer_note" => o["buyer_note"].to_s.presence || o["remarks"].to_s.presence,
            "buyer_first_name" => o["customer_first_name"].to_s.presence,
            "buyer_last_name" => o["customer_last_name"].to_s.presence,

            "amount" => o["price"].to_s.presence,
            "payment_method" => o["payment_method"].to_s.presence,
            "delivery_info" => o["delivery_info"].to_s.presence,
            "warehouse_code" => o["warehouse_code"].to_s.presence,
            "shipping_fee" => o["shipping_fee"].to_s.presence,
            "shipping_fee_original" => o["shipping_fee_original"].to_s.presence,
            "shipping_fee_discount_platform" => o["shipping_fee_discount_platform"].to_s.presence,
            "shipping_fee_discount_seller" => o["shipping_fee_discount_seller"].to_s.presence,

            "address_shipping" => compact_hash(
              "first_name" => shipping["first_name"],
              "last_name" => shipping["last_name"],
              "phone" => shipping["phone"],
              "phone2" => shipping["phone2"],
              "address1" => shipping["address1"],
              "address2" => shipping["address2"],
              "address3" => shipping["address3"],
              "address4" => shipping["address4"],
              "address5" => shipping["address5"],
              "city" => shipping["city"],
              "district" => shipping["addressDsitrict"],
              "post_code" => shipping["post_code"],
              "country" => shipping["country"]
            ),
            "address_billing" => compact_hash(
              "first_name" => billing["first_name"],
              "last_name" => billing["last_name"],
              "phone" => billing["phone"],
              "phone2" => billing["phone2"],
              "address1" => billing["address1"],
              "address2" => billing["address2"],
              "address3" => billing["address3"],
              "address4" => billing["address4"],
              "address5" => billing["address5"],
              "city" => billing["city"],
              "district" => billing["addressDsitrict"],
              "post_code" => billing["post_code"],
              "country" => billing["country"]
            ),
            "recipient_info" => compact_hash(
              "identify_no" => o.dig("recipient_info", "identify_no"),
              "detail_address" => o.dig("recipient_info", "detail_address"),
              "passport_no" => o.dig("recipient_info", "passport_no")
            ),

            "line_items" => order_items.map do |li|
              {
                "id" => li["order_item_id"].to_s,
                "seller_sku" => li["sku"].to_s,
                "quantity" => extract_quantity(li),
                "display_status" => li["status"].to_s,
                "tracking_number" => li["tracking_code"].to_s.presence || li["tracking_number"].to_s.presence,
                "shipment_provider" => li["shipment_provider"].to_s.presence || li["shipping_provider"].to_s.presence
              }.compact
            end
          }.compact
        end
      end

      def self.build_buyer_name(order)
        first = order["customer_first_name"].to_s.strip
        last = order["customer_last_name"].to_s.strip
        full = [ first, last ].reject(&:empty?).join(" ")
        full.presence
      end

      def self.extract_province(order)
        shipping = order["address_shipping"] || {}
        billing = order["address_billing"] || {}

        shipping["city"].to_s.presence ||
          billing["city"].to_s.presence
      end

      def self.compact_hash(hash)
        hash.transform_values { |v| v.to_s.presence }.compact
      end

      def self.derive_status(order:, items:)
        item_statuses = Array(items).map { |i| i["status"].to_s.downcase.strip }.reject(&:empty?).uniq
        order_statuses = Array(order["statuses"]).map { |s| s.to_s.downcase.strip }.reject(&:empty?).uniq
        statuses = (item_statuses + order_statuses).uniq

        has_tracking =
          Array(items).any? do |item|
            Orders::StatusTracking.present?(item["tracking_code"]) ||
              Orders::StatusTracking.present?(item["tracking_number"])
          end

        return "CANCELLED" if statuses.any? { |s| cancelled_status?(s) }
        return "DELIVERED" if statuses.any? { |s| delivered_status?(s) }
        return "IN_TRANSIT" if statuses.any? { |s| in_transit_status?(s) }

        # ถ้ามี tracking แล้ว อย่างน้อยต้องเป็น READY_TO_SHIP
        return "READY_TO_SHIP" if has_tracking

        return "READY_TO_SHIP" if statuses.any? { |s| ready_to_ship_status?(s) }
        return "AWAITING_FULFILLMENT" if statuses.any? { |s| awaiting_fulfillment_status?(s) }

        "AWAITING_FULFILLMENT"
      end

      def self.cancelled_status?(status)
        %w[
          canceled cancelled cancel
          failed
          returned
          return_failed
        ].include?(status)
      end

      def self.delivered_status?(status)
        %w[
          delivered
          completed
          shipped_back_success
        ].include?(status)
      end

      def self.in_transit_status?(status)
        %w[
          shipped
        ].include?(status)
      end

      def self.ready_to_ship_status?(status)
        %w[
          ready_to_ship
          packed
        ].include?(status)
      end

      def self.awaiting_fulfillment_status?(status)
        %w[
          confirmed
          unpaid
          topack
          to_pack
          pending
        ].include?(status)
      end

      def self.parse_time_to_i(value)
        return 0 if value.blank?
        Time.parse(value.to_s).to_i
      rescue
        0
      end

      def self.extract_quantity(item)
        qty = item["quantity"] || item["item_quantity"] || 1
        q = qty.to_i
        q > 0 ? q : 1
      end
    end
  end
end

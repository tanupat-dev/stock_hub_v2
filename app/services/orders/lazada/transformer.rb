# frozen_string_literal: true

require "time"

module Orders
  module Lazada
    class Transformer
      def self.call(orders:, items:)
        items_by_order = Array(items).index_by { |i| i["order_id"].to_s }

        Array(orders).map do |order|
          bucket = items_by_order[order["order_id"].to_s] || {}
          order_items = Array(bucket["order_items"])

          shipping = order["address_shipping"] || {}
          billing = order["address_billing"] || {}

          {
            "id" => order["order_id"].to_s,
            "status" => normalize_status(order:, items: order_items),
            "update_time" => parse_time_to_i(order["updated_at"]),
            "created_at" => order["created_at"].to_s.presence,
            "updated_at" => order["updated_at"].to_s.presence,

            "buyer_name" => build_buyer_name(order),
            "province" => extract_province(order),
            "buyer_note" => order["buyer_note"].to_s.presence || order["remarks"].to_s.presence,
            "buyer_first_name" => order["customer_first_name"].to_s.presence,
            "buyer_last_name" => order["customer_last_name"].to_s.presence,

            "amount" => order["price"].to_s.presence,
            "payment_method" => order["payment_method"].to_s.presence,
            "delivery_info" => order["delivery_info"].to_s.presence,
            "warehouse_code" => order["warehouse_code"].to_s.presence,
            "shipping_fee" => order["shipping_fee"].to_s.presence,
            "shipping_fee_original" => order["shipping_fee_original"].to_s.presence,
            "shipping_fee_discount_platform" => order["shipping_fee_discount_platform"].to_s.presence,
            "shipping_fee_discount_seller" => order["shipping_fee_discount_seller"].to_s.presence,

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
              "identify_no" => order.dig("recipient_info", "identify_no"),
              "detail_address" => order.dig("recipient_info", "detail_address"),
              "passport_no" => order.dig("recipient_info", "passport_no")
            ),

            "line_items" => order_items.map do |item|
              {
                "id" => item["order_item_id"].to_s,
                "seller_sku" => item["sku"].to_s,
                "quantity" => extract_quantity(item),
                "display_status" => item["status"].to_s,
                "tracking_number" => extract_tracking_number(item),
                "shipment_provider" => item["shipment_provider"].to_s.presence || item["shipping_provider"].to_s.presence
              }.compact
            end
          }.compact
        end
      end

      def self.normalize_status(order:, items:)
        statuses = normalized_statuses(order:, items:)
        has_tracking = Orders::StatusTracking.any_in_order_payload?(
          order.merge("line_items" => items)
        )

        # 1) cancel / reverse / failed กลุ่มที่ต้องไม่ไป reserve/commit ต่อ
        return "CANCELLED" if statuses.any? { |status| cancelled_status?(status) }
        return "CANCELLED" if statuses.any? { |status| reverse_or_failed_status?(status) }

        # 2) delivered flow
        return "DELIVERED" if statuses.any? { |status| delivered_status?(status) }

        # 3) in transit
        return "IN_TRANSIT" if statuses.any? { |status| in_transit_status?(status) }

        # 4) pre-ship flow แบบเดียวกับ tiktok:
        #    ยังไม่พร้อมจัดส่ง = ไม่มี tracking
        #    พร้อมจัดส่งแล้ว = มี tracking
        if statuses.any? { |status| pre_ship_status?(status) }
          return has_tracking ? "READY_TO_SHIP" : "AWAITING_FULFILLMENT"
        end

        # 5) fallback:
        #    ถ้ามี tracking ให้ถือว่า READY_TO_SHIP
        #    ถ้าไม่มี tracking ให้ถือว่า AWAITING_FULFILLMENT
        has_tracking ? "READY_TO_SHIP" : "AWAITING_FULFILLMENT"
      end

      def self.normalized_statuses(order:, items:)
        item_statuses =
          Array(items)
            .map { |item| item["status"].to_s.downcase.strip }
            .reject(&:blank?)

        order_statuses =
          Array(order["statuses"])
            .map { |status| status.to_s.downcase.strip }
            .reject(&:blank?)

        (item_statuses + order_statuses).uniq
      end

      def self.cancelled_status?(status)
        %w[
          canceled
          cancelled
          cancel
        ].include?(status)
      end

      def self.reverse_or_failed_status?(status)
        status.start_with?("shipped_back") ||
          %w[
            returned
            return_failed
            failed_delivery
            lost_by_3pl
            damaged_by_3pl
          ].include?(status)
      end

      def self.delivered_status?(status)
        %w[
          delivered
          confirmed
        ].include?(status)
      end

      def self.in_transit_status?(status)
        %w[
          shipped
        ].include?(status)
      end

      def self.pre_ship_status?(status)
        %w[
          pending
          unpaid
          packed
          ready_to_ship_pending
          ready_to_ship
          topack
          to_pack
          toship
          to_ship
          readytoship
          confirmed_pending
        ].include?(status)
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

      def self.extract_tracking_number(item)
        item["tracking_code"].to_s.presence ||
          item["tracking_number"].to_s.presence
      end

      def self.compact_hash(hash)
        hash.transform_values { |value| value.to_s.presence }.compact
      end

      def self.parse_time_to_i(value)
        return 0 if value.blank?

        Time.parse(value.to_s).to_i
      rescue StandardError
        0
      end

      def self.extract_quantity(item)
        qty = item["quantity"] || item["item_quantity"] || 1
        qty_i = qty.to_i
        qty_i > 0 ? qty_i : 1
      end
    end
  end
end

# frozen_string_literal: true

module Orders
  module Shopee
    class StatusMapper
      class UnknownStatus < StandardError; end

      def self.call(value, tracking_number: nil)
        raw = normalize(value)
        has_tracking = Orders::StatusTracking.present?(tracking_number)

        return "CANCELLED" if raw.include?("ยกเลิกแล้ว")
        return "AWAITING_FULFILLMENT" if raw.include?("ยังไม่ชำระ")

        if raw.include?("ที่ต้องจัดส่ง") || raw.include?("รอการจัดส่ง")
          return has_tracking ? "READY_TO_SHIP" : "AWAITING_FULFILLMENT"
        end

        return "IN_TRANSIT" if raw == "การจัดส่ง"
        return "IN_TRANSIT" if raw.include?("กำลังจัดส่ง")

        return "DELIVERED" if raw.include?("ผู้ซื้อได้รับสินค้าแล้ว")
        return "DELIVERED" if raw.include?("จัดส่งสำเร็จแล้ว")
        return "DELIVERED" if raw.include?("สำเร็จแล้ว")

        nil
      end

      def self.call!(value, tracking_number: nil)
        mapped = call(value, tracking_number: tracking_number)
        return mapped if mapped.present?

        raise UnknownStatus, "unknown shopee status: #{value}"
      end

      def self.normalize(value)
        value.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end

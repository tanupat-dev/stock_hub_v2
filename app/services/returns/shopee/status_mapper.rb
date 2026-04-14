# frozen_string_literal: true

module Returns
  module Shopee
    class StatusMapper
      def self.call(value)
        raw = normalize(value)

        return "completed" if raw.include?("คืนเงินแล้ว")
        return "completed" if raw.include?("เสร็จสิ้น")
        return "completed" if raw.include?("สำเร็จ")

        return "shipped_back" if raw.include?("จัดส่งสินค้าคืนสำเร็จ")
        return "shipped_back" if raw.include?("ผู้ซื้อส่งคืนแล้ว")
        return "shipped_back" if raw.include?("กำลังส่งคืน")
        return "shipped_back" if raw.include?("ส่งคืนสินค้า")

        return "requested" if raw.present?

        "requested"
      end

      def self.normalize(value)
        value.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end

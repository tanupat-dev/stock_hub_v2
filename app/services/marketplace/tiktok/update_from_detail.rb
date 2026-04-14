# frozen_string_literal: true

module Marketplace
  module Tiktok
    class UpdateFromDetail
      def self.call!(order:, payload:)
        new(order, payload).call!
      end

      def initialize(order, payload)
        @order = order
        @payload = payload
      end

      def call!
        buyer_name = extract_buyer_name
        province   = extract_province
        buyer_note = extract_buyer_note

        updates = {}

        updates[:buyer_name] = buyer_name if buyer_name.present?
        updates[:province]   = province if province.present?
        updates[:buyer_note] = buyer_note if buyer_note.present?

        return if updates.empty?

        @order.update_columns(updates.merge(updated_at: Time.current))
      end

      private

      def extract_buyer_name
        @payload.dig("recipient_address", "name").to_s.strip.presence
      end

      def extract_province
        district_info = Array(@payload.dig("recipient_address", "district_info"))

        district_info.find { |r| r["address_level"].to_s == "L1" }
                     &.dig("address_name")
                     .to_s
                     .strip
                     .presence
      end

      def extract_buyer_note
        @payload["buyer_message"].to_s.strip.presence
      end
    end
  end
end

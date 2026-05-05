# frozen_string_literal: true

module Orders
  module Tiktok
    class UpdateFromDetail
      def self.call!(order:, payload:)
        new(order, payload).call!
      end

      def initialize(order, payload)
        @order = order
        @payload = payload || {}
      end

      def call!
        previous_status = @order.status.to_s.presence

        buyer_name = extract_buyer_name
        province   = extract_province
        buyer_note = extract_buyer_note

        merged_payload = merged_raw_payload

        updates = {
          raw_payload: merged_payload,
          updated_at: Time.current
        }

        updates[:buyer_name] = buyer_name if buyer_name.present?
        updates[:province]   = province if province.present?
        updates[:buyer_note] = buyer_note if buyer_note.present?

        @order.update_columns(updates)

        Orders::Tiktok::UpsertLines.call!(
          shop: @order.shop,
          order: @order,
          raw_order: merged_payload
        )

        external_skus = Array(merged_payload["line_items"])
          .map { |li| li["seller_sku"].to_s.strip }
          .reject(&:blank?)
          .uniq

        remap_result = Inventory::RemapSkuReferences.call!(
          shop: @order.shop,
          channel: "tiktok",
          external_skus: external_skus
        )

        repair_result = Orders::RepairMissingInventoryActions.call!(
          order: @order,
          raw_order: merged_payload,
          previous_status: previous_status,
          source: "tiktok_detail_update"
        )

        {
          ok: true,
          order_id: @order.id,
          external_order_id: @order.external_order_id,
          remap_result: remap_result,
          repair_result: repair_result
        }
      end

      private

      def merged_raw_payload
        existing = (@order.raw_payload || {}).deep_dup

        existing["line_items"] = @payload["line_items"] if @payload["line_items"].present?
        existing["recipient_address"] = @payload["recipient_address"] if @payload["recipient_address"].present?
        existing["buyer_message"] = @payload["buyer_message"] if @payload["buyer_message"].present?
        existing["shipping_provider"] = @payload["shipping_provider"] if @payload["shipping_provider"].present?
        existing["tracking_number"] = @payload["tracking_number"] if @payload["tracking_number"].present?
        existing["update_time"] = @payload["update_time"] if @payload["update_time"].present?
        existing["status"] = @payload["status"] if @payload["status"].present?

        existing
      end

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

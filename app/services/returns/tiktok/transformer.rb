# frozen_string_literal: true

module Returns
  module Tiktok
    class Transformer
      RECEIVED_RETURN_EVENTS = %w[
        RETURN_DELIVERED
        RETURN_RECEIVED
        SELLER_RECEIVED_RETURN
        SELLER_CONFIRM_RECEIVE
        WAREHOUSE_RECEIVED_RETURN
      ].freeze

      RECEIVED_RETURN_KEYWORDS = [
        "seller received",
        "seller confirm receive",
        "returned package approved by seller",
        "warehouse received",
        "returned item received",
        "received the returned item",
        "return has been delivered"
      ].freeze

      PHYSICAL_RETURN_EVENTS = %w[
        BUYER_SHIPPED
        RETURN_DELIVERED
        RETURN_RECEIVED
        SELLER_RECEIVED_RETURN
        SELLER_CONFIRM_RECEIVE
        WAREHOUSE_RECEIVED_RETURN
        SELLER_REJECT_RECEIVE_DELIVERED_TIMEOUT
      ].freeze

      RETURN_TYPE_VALUES = %w[
        RETURN
        RETURN_AND_REFUND
      ].freeze

      def self.call(raw_return:, records: nil)
        new(raw_return: raw_return, records: records).call
      end

      def initialize(raw_return:, records:)
        @raw_return = raw_return || {}
        @records = normalize_records(records)
      end

      def call
        {
          "external_return_id" => @raw_return["return_id"].to_s,
          "external_order_id" => @raw_return["order_id"].to_s,
          "tracking_number" => @raw_return["return_tracking_number"].to_s.presence,
          "status_marketplace" => Returns::Tiktok::StatusMapper.call(
            return_status: @raw_return["return_status"]
          ),
          "status_marketplace_raw" => @raw_return["return_status"].to_s,
          "requested_at" => to_time(@raw_return["create_time"]),
          "return_carrier_method" => extract_return_carrier_method,
          "return_delivery_status" => @raw_return["return_status"].to_s.presence,
          "returned_delivered_at" => extract_returned_delivered_at,
          "buyer_username" => extract_buyer_username,
          "is_return" => physical_return?,
          "raw_payload" => {
            "source" => "tiktok_return_api",
            "return" => @raw_return,
            "records" => { "records" => @records }
          },
          "lines" => build_lines
        }
      end

      private

      def normalize_records(records)
        Array((records || {})["records"]).compact
      end

      def build_lines
        line_items = Array(@raw_return["return_line_items"])

        line_items.flat_map do |line|
          sub_lines = Array(line["return_sub_line_items"])

          if sub_lines.any?
            sub_lines.map do |sub|
              {
                "external_line_id" => sub["return_sub_line_item_id"].to_s.presence || sub["sub_order_line_item_id"].to_s.presence,
                "order_line_item_id" => sub["order_line_item_id"].to_s.presence || line["order_line_item_id"].to_s.presence,
                "external_sku" => sub["seller_sku"].to_s.presence || line["seller_sku"].to_s.presence,
                "qty_returned" => normalize_qty(sub["quantity"]) || 1,
                "raw_payload" => line.deep_merge("return_sub_line_item" => sub)
              }
            end
          else
            {
              "external_line_id" => line["return_line_item_id"].to_s.presence || line["order_line_item_id"].to_s.presence,
              "order_line_item_id" => line["order_line_item_id"].to_s.presence,
              "external_sku" => line["seller_sku"].to_s.presence,
              "qty_returned" => normalize_qty(line["quantity"]) || 1,
              "raw_payload" => line
            }
          end
        end
      end

      def extract_returned_delivered_at
        delivered_record = matched_delivered_record
        return nil if delivered_record.blank?

        to_time(delivered_record["create_time"])
      end

      def matched_delivered_record
        @records.find do |record|
          event = record["event"].to_s.strip.upcase
          desc = record["description"].to_s.strip.downcase
          note = record["note"].to_s.strip.downcase

          RECEIVED_RETURN_EVENTS.include?(event) ||
            RECEIVED_RETURN_KEYWORDS.any? { |keyword| desc.include?(keyword) || note.include?(keyword) }
        end
      end

      def physical_return?
        raw_type = @raw_return["return_type"].to_s.strip.upcase
        return true if RETURN_TYPE_VALUES.include?(raw_type)

        @records.any? do |record|
          PHYSICAL_RETURN_EVENTS.include?(record["event"].to_s.strip.upcase)
        end
      end

      def extract_return_carrier_method
        @raw_return["return_provider_name"].to_s.presence ||
          @raw_return["return_method"].to_s.presence ||
          @raw_return["shipment_type"].to_s.presence
      end

      def extract_buyer_username
        @raw_return["buyer_username"].to_s.presence ||
          @raw_return["buyer_nickname"].to_s.presence
      end

      def normalize_qty(value)
        qty = value.to_i
        return nil if qty <= 0

        qty
      end

      def to_time(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        ts = raw.to_i
        return nil if ts <= 0

        Time.at(ts)
      end
    end
  end
end

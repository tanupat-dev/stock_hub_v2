# frozen_string_literal: true

require "time"

module Returns
  module Shopee
    class Transformer
      def self.call(group_key:, rows:)
        new(group_key:, rows:).call
      end

      def initialize(group_key:, rows:)
        @group_key = group_key
        @rows = Array(rows)
      end

      def call
        first = @rows.first
        raise ArgumentError, "rows are required" if first.nil?

        {
          "external_return_id" => first.fetch(:external_return_id).to_s.strip,
          "external_order_id" => first.fetch(:external_order_id).to_s.strip,
          "status_marketplace" => Returns::Shopee::StatusMapper.call(first[:status_marketplace]),
          "status_marketplace_raw" => first[:status_marketplace].to_s.strip,
          "tracking_number" => blank_nil(first[:tracking_number]),
          "requested_at" => parse_time(first[:requested_at_raw]),
          "return_carrier_method" => blank_nil(first[:return_carrier_method]),
          "return_delivery_status" => blank_nil(first[:return_delivery_status]),
          "returned_delivered_at" => parse_time(first[:returned_delivered_at_raw]),
          "buyer_username" => blank_nil(first[:buyer_username]),
          "raw_payload" => {
            "source" => "shopee_return_excel",
            "group_key" => @group_key,
            "row_count" => @rows.size,
            "status_marketplace_raw" => first[:status_marketplace].to_s.strip,
            "return_delivery_status_raw" => first[:return_delivery_status].to_s.strip,
            "rows" => @rows.map { |r| serialize_row(r) }
          },
          "lines" => build_lines
        }
      end

      private

      def build_lines
        @rows
          .group_by { |r| r[:sku_code].to_s.strip }
          .map do |sku_code, grouped_rows|
            sample = grouped_rows.first

            {
              "external_line_id" => "#{sample[:external_return_id]}:#{sku_code}",
              "sku_code_snapshot" => sku_code,
              "qty_returned" => grouped_rows.sum { |r| normalize_qty(r[:qty_returned]) },
              "raw_payload" => {
                "source" => "shopee_return_excel",
                "sku_code" => sku_code,
                "rows" => grouped_rows.map { |r| serialize_row(r) }
              }
            }
          end
      end

      def serialize_row(row)
        {
          "external_return_id" => row[:external_return_id],
          "external_order_id" => row[:external_order_id],
          "sku_code" => row[:sku_code],
          "qty_returned" => normalize_qty(row[:qty_returned]),
          "status_marketplace" => row[:status_marketplace],
          "tracking_number" => row[:tracking_number],
          "requested_at_raw" => row[:requested_at_raw],
          "return_carrier_method" => row[:return_carrier_method],
          "return_delivery_status" => row[:return_delivery_status],
          "returned_delivered_at_raw" => row[:returned_delivered_at_raw],
          "buyer_username" => row[:buyer_username]
        }
      end

      def normalize_qty(value)
        qty = value.to_i
        qty.positive? ? qty : 1
      end

      def blank_nil(value)
        raw = value.to_s.strip
        raw.presence
      end

      def parse_time(value)
        return nil if value.blank?

        Time.parse(value.to_s)
      rescue
        nil
      end
    end
  end
end

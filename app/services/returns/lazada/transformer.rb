# frozen_string_literal: true

module Returns
  module Lazada
    class Transformer
      def self.call(summary:, detail:)
        new(summary: summary, detail: detail).call
      end

      def initialize(summary:, detail:)
        @summary = summary || {}
        @detail = detail || {}
      end

      def call
        reverse_order_id = @detail["reverse_order_id"].to_s.presence || @summary["reverse_order_id"].to_s
        trade_order_id = @detail["trade_order_id"].to_s.presence || @summary["trade_order_id"].to_s
        request_type = @detail["request_type"].to_s.presence || @summary["request_type"].to_s

        detail_lines = Array(@detail["reverseOrderLineDTOList"])
        summary_lines = Array(@summary["reverse_order_lines"])
        merged_lines = merge_lines(summary_lines: summary_lines, detail_lines: detail_lines)

        {
          "external_return_id" => reverse_order_id,
          "external_order_id" => trade_order_id,
          "tracking_number" => merged_lines.map { |li| li["tracking_number"].to_s.strip.presence }.compact.first,
          "status_marketplace" => derive_status_marketplace(merged_lines, request_type: request_type),
          "status_marketplace_raw" => {
            "request_type" => request_type,
            "reverse_statuses" => merged_lines.map { |li| li["reverse_status"].to_s }.uniq,
            "ofc_statuses" => merged_lines.map { |li| li["ofc_status"].to_s }.uniq
          },
          "requested_at" => extract_requested_at(merged_lines),
          "return_carrier_method" => @detail["shipping_type"].to_s.presence || @summary["shipping_type"].to_s.presence,
          "return_delivery_status" => merged_lines.map { |li| li["ofc_status"].to_s.strip }.reject(&:blank?).uniq.join(", ").presence,
          "returned_delivered_at" => extract_returned_delivered_at(merged_lines),
          "buyer_username" => merged_lines.map { |li| li.dig("buyer", "user_id").to_s.strip.presence || li.dig("buyer", "buyer_id").to_s.strip.presence }.compact.first,
          "raw_payload" => {
            "source" => "lazada_reverse_api",
            "summary" => @summary,
            "detail" => @detail
          },
          "lines" => build_lines(merged_lines)
        }
      end

      private

      def build_lines(lines)
        lines.map do |li|
          external_sku =
            li["seller_sku_id"].to_s.presence ||
            li.dig("product", "product_sku").to_s.presence ||
            li.dig("productDTO", "sku").to_s.presence

          external_line_id =
            li["reverse_order_line_id"].to_s.presence ||
            li["trade_order_line_id"].to_s.presence

          quantity =
            li["quantity"].to_i.nonzero? ||
            li["item_quantity"].to_i.nonzero? ||
            1

          {
            "external_line_id" => external_line_id,
            "external_sku" => external_sku,
            "qty_returned" => quantity,
            "raw_payload" => li
          }
        end
      end

      def derive_status_marketplace(lines, request_type:)
        reverse_statuses = lines.map { |li| li["reverse_status"] }.compact
        ofc_statuses = lines.map { |li| li["ofc_status"] }.compact

        Returns::Lazada::StatusMapper.call(
          reverse_status: reverse_statuses.last,
          ofc_status: ofc_statuses.last,
          request_type: request_type
        )
      end

      def extract_requested_at(lines)
        timestamps = lines.map { |li| to_time(li["return_order_line_gmt_create"]) }.compact
        timestamps.min
      end

      def extract_returned_delivered_at(lines)
        completed_line = lines.find do |li|
          Returns::Lazada::StatusMapper.completed?(
            li["reverse_status"].to_s.upcase,
            li["ofc_status"].to_s.upcase,
            nil
          )
        end
        return nil if completed_line.nil?

        to_time(completed_line["return_order_line_gmt_modified"])
      end

      def to_time(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        n = raw.to_i
        return nil if n <= 0

        if n >= 1_000_000_000_000
          Time.at(n / 1000.0)
        else
          Time.at(n)
        end
      end

      def merge_lines(summary_lines:, detail_lines:)
        detail_by_id = Array(detail_lines).index_by { |li| li["reverse_order_line_id"].to_s }

        merged = Array(summary_lines).map do |summary_line|
          id = summary_line["reverse_order_line_id"].to_s
          detail_line = detail_by_id[id] || {}
          summary_line.deep_merge(detail_line)
        end

        merged.presence || Array(detail_lines)
      end
    end
  end
end

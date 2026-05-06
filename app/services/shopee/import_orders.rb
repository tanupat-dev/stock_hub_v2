# frozen_string_literal: true

require "roo"
require "time"

module Shopee
  class ImportOrders
    REQUIRED_HEADERS = [
      "หมายเลขคำสั่งซื้อ",
      "สถานะการสั่งซื้อ",
      "เลขอ้างอิง SKU (SKU Reference No.)",
      "จำนวน",
      "วันที่ทำการสั่งซื้อ",
      "*หมายเลขติดตามพัสดุ",
      "ชื่อผู้รับ",
      "จังหวัด",
      "หมายเหตุจากผู้ซื้อ"
    ].freeze

    def self.parse_rows!(filepath)
      new(shop: nil, filepath: filepath, source_filename: File.basename(filepath.to_s)).load_rows!
    end

    def self.call!(shop:, filepath: nil, rows: nil, source_filename: nil, batch: nil)
      new(
        shop: shop,
        filepath: filepath,
        rows: rows,
        source_filename: source_filename,
        batch: batch
      ).call!
    end

    def initialize(shop:, filepath: nil, rows: nil, source_filename:, batch: nil)
      @shop = shop
      @filepath = filepath
      @rows = rows
      @source_filename =
        source_filename.presence ||
        (filepath.present? ? File.basename(filepath.to_s) : "shopee_orders.xlsx")
      @batch = batch
    end

    def call!
      batch = prepare_batch!

      rows = normalized_rows
      grouped = group_rows_by_order(rows)

      success_orders = 0
      failed_orders = 0
      success_rows = 0
      failed_rows = 0
      errors = []
      unknown_statuses = Hash.new(0)

      grouped.each do |external_order_id, order_rows|
        begin
          raw_order = build_raw_order(external_order_id, order_rows)
          Orders::Shopee::Upsert.call!(shop: @shop, raw_order: raw_order)

          success_orders += 1
          success_rows += order_rows.size
        rescue Orders::Shopee::StatusMapper::UnknownStatus => e
          failed_orders += 1
          failed_rows += order_rows.size
          unknown_statuses[extract_status_text(order_rows)] += 1

          errors << {
            order_id: external_order_id,
            type: "unknown_status",
            status_text: extract_status_text(order_rows),
            err_class: e.class.name,
            err_message: e.message
          }
        rescue => e
          failed_orders += 1
          failed_rows += order_rows.size

          errors << {
            order_id: external_order_id,
            type: "upsert_error",
            status_text: extract_status_text(order_rows),
            err_class: e.class.name,
            err_message: e.message
          }
        end
      end

      batch.update!(
        total_rows: rows.size,
        success_rows: success_rows,
        failed_rows: failed_rows,
        meta: {
          grouped_orders: grouped.size,
          success_orders: success_orders,
          failed_orders: failed_orders,
          unknown_statuses: unknown_statuses.sort.to_h,
          errors: errors.first(100)
        },
        error_summary: build_error_summary(errors, unknown_statuses),
        status: failed_orders.positive? ? "completed_with_errors" : "completed",
        finished_at: Time.current
      )

      {
        ok: failed_orders.zero?,
        batch_id: batch.id,
        total_rows: rows.size,
        grouped_orders: grouped.size,
        success_orders: success_orders,
        failed_orders: failed_orders,
        success_rows: success_rows,
        failed_rows: failed_rows,
        unknown_statuses: unknown_statuses.sort.to_h
      }
    rescue => e
      batch&.update!(
        status: "failed",
        error_summary: "#{e.class}: #{e.message}",
        finished_at: Time.current
      )
      raise
    end

    def load_rows!
      raise ArgumentError, "filepath is required" if @filepath.blank?

      xlsx = Roo::Excelx.new(@filepath)
      sheet = xlsx.sheet(0)

      header = sheet.row(1).map { |v| v.to_s.strip }
      missing = REQUIRED_HEADERS - header
      raise "missing required headers: #{missing.join(', ')}" if missing.any?

      idx = header.each_with_index.to_h
      out = []

      (2..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)

        order_id = cell(row, idx, "หมายเลขคำสั่งซื้อ")
        next if order_id.blank?

        out << {
          order_id: order_id,
          status_th: cell(row, idx, "สถานะการสั่งซื้อ"),
          sku_reference: cell(row, idx, "เลขอ้างอิง SKU (SKU Reference No.)"),
          quantity: cell(row, idx, "จำนวน").to_i,
          ordered_at_raw: cell(row, idx, "วันที่ทำการสั่งซื้อ"),
          tracking_number: cell(row, idx, "*หมายเลขติดตามพัสดุ"),
          buyer_name: cell(row, idx, "ชื่อผู้รับ"),
          province: cell(row, idx, "จังหวัด"),
          buyer_note: cell(row, idx, "หมายเหตุจากผู้ซื้อ")
        }
      end

      out
    end

    private

    def prepare_batch!
      if @batch.present?
        @batch.update!(
          status: "processing",
          started_at: @batch.started_at || Time.current,
          error_summary: nil
        )

        return @batch
      end

      FileBatch.create!(
        channel: "shopee",
        shop: @shop,
        kind: "shopee_order_import",
        status: "processing",
        source_filename: @source_filename,
        started_at: Time.current
      )
    end

    def normalized_rows
      raw_rows = @rows || load_rows!

      raw_rows.map do |row|
        {
          order_id: read_row_value(row, :order_id),
          status_th: read_row_value(row, :status_th),
          sku_reference: read_row_value(row, :sku_reference),
          quantity: read_row_value(row, :quantity).to_i,
          ordered_at_raw: read_row_value(row, :ordered_at_raw),
          tracking_number: read_row_value(row, :tracking_number),
          buyer_name: read_row_value(row, :buyer_name),
          province: read_row_value(row, :province),
          buyer_note: read_row_value(row, :buyer_note)
        }
      end
    end

    def read_row_value(row, key)
      row[key] || row[key.to_s]
    end

    def group_rows_by_order(rows)
      rows.group_by { |r| r[:order_id].to_s }
    end

    def build_raw_order(external_order_id, order_rows)
      first = order_rows.first
      tracking_number = first[:tracking_number]

      canonical_status = Orders::Shopee::StatusMapper.call!(
        first[:status_th],
        tracking_number: tracking_number
      )

      ordered_at = parse_time(first[:ordered_at_raw])

      {
        "id" => external_order_id,
        "status" => canonical_status,
        "ordered_at" => ordered_at,
        "ordered_at_ts" => ordered_at&.to_i,
        "tracking_number" => tracking_number,
        "buyer_name" => first[:buyer_name],
        "province" => first[:province],
        "buyer_note" => first[:buyer_note],
        "line_items" => order_rows.map do |r|
          {
            "id" => "#{external_order_id}:#{r[:sku_reference]}",
            "sku_reference" => r[:sku_reference].to_s.strip,
            "quantity" => [ r[:quantity].to_i, 1 ].max,
            "display_status" => r[:status_th].to_s
          }
        end
      }
    end

    def extract_status_text(order_rows)
      order_rows.first[:status_th].to_s.strip
    end

    def build_error_summary(errors, unknown_statuses)
      parts = []

      if unknown_statuses.any?
        parts << "Unknown statuses:"
        unknown_statuses.sort.each do |status_text, count|
          parts << "- #{status_text}: #{count}"
        end
      end

      if errors.any?
        parts << ""
        parts << "Sample errors:"
        errors.first(10).each do |e|
          parts << "- #{e[:order_id]} [#{e[:type]}]: #{e[:err_class]} #{e[:err_message]}"
        end
      end

      text = parts.join("\n")
      text.presence
    end

    def parse_time(value)
      return nil if value.blank?

      Time.find_zone!("Asia/Bangkok").parse(value.to_s)
    rescue
      nil
    end

    def cell(row, idx, header_name)
      pos = idx.fetch(header_name)
      row[pos].to_s.strip
    end
  end
end

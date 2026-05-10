# frozen_string_literal: true

require "csv"
require "roo"
require "fileutils"
require "securerandom"

module Shopee
  class ImportFailedDeliveries
    REQUIRED_HEADERS = [
      "หมายเลขคำสั่งซื้อ",
      "สถานะการสั่งซื้อ",
      "จัดส่งไม่สำเร็จ",
      "*หมายเลขติดตามพัสดุ",
      "เลขอ้างอิง SKU (SKU Reference No.)",
      "จำนวน"
    ].freeze

    def self.call!(shop:, filepath:, source_filename: nil)
      new(shop:, filepath:, source_filename:).call!
    end

    def initialize(shop:, filepath:, source_filename:)
      @shop = shop
      @filepath = filepath
      @source_filename = source_filename.presence || File.basename(filepath.to_s)
    end

    def call!
      batch = FileBatch.create!(
        channel: "shopee",
        shop: @shop,
        kind: "shopee_failed_delivery_import",
        status: "processing",
        source_filename: @source_filename,
        started_at: Time.current
      )

      rows = load_rows!
      rows = rows.select { |row| failed_delivery_row?(row) }
      grouped = rows.group_by { |row| row[:external_order_id].to_s }

      success_returns = 0
      failed_returns = 0
      success_rows = 0
      failed_rows = 0
      errors = []

      grouped.each do |external_order_id, order_rows|
        begin
          raw_failed_delivery = build_raw_failed_delivery(external_order_id, order_rows)

          Returns::Shopee::CreateFromFailedDelivery.call!(
            shop: @shop,
            raw_failed_delivery: raw_failed_delivery
          )

          success_returns += 1
          success_rows += order_rows.size
        rescue => e
          failed_returns += 1
          failed_rows += order_rows.size

          errors << {
            external_order_id: external_order_id,
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
          grouped_failed_deliveries: grouped.size,
          success_returns: success_returns,
          failed_returns: failed_returns,
          errors: errors.first(100)
        },
        error_summary: build_error_summary(errors),
        status: failed_returns.positive? ? "completed_with_errors" : "completed",
        finished_at: Time.current
      )

      {
        ok: failed_returns.zero?,
        batch_id: batch.id,
        total_rows: rows.size,
        grouped_failed_deliveries: grouped.size,
        success_returns: success_returns,
        failed_returns: failed_returns,
        success_rows: success_rows,
        failed_rows: failed_rows
      }
    rescue => e
      batch&.update!(
        status: "failed",
        error_summary: "#{e.class}: #{e.message}",
        finished_at: Time.current
      )
      raise
    end

    private

    def load_rows!
      ext = File.extname(@filepath.to_s).downcase

      if ext == ".csv"
        load_csv_rows!
      else
        load_excel_rows!
      end
    end

    def load_csv_rows!
      text = File.read(@filepath, encoding: "bom|utf-8")
      csv = CSV.parse(text, headers: true)

      header = csv.headers.map { |h| h.to_s.strip }
      validate_headers!(header)

      csv.map do |row|
        build_row(row.to_h)
      end
    end

    def load_excel_rows!
      workbook = Roo::Excelx.new(@filepath)
      sheet = workbook.sheet(0)

      header = sheet.row(1).map { |v| v.to_s.strip }
      validate_headers!(header)

      idx = header.each_with_index.to_h
      rows = []

      (2..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)
        values = header.index_with { |h| cell(row, idx, h) }
        rows << build_row(values)
      end

      rows
    end

    def validate_headers!(header)
      missing = REQUIRED_HEADERS - header
      raise "missing required headers: #{missing.join(', ')}" if missing.any?
    end

    def build_row(values)
      {
        external_order_id: values["หมายเลขคำสั่งซื้อ"].to_s.strip,
        order_status_raw: values["สถานะการสั่งซื้อ"].to_s.strip,
        refund_return_status_raw: values["สถานะการคืนเงินหรือคืนสินค้า"].to_s.strip,
        failed_delivery_status: values["จัดส่งไม่สำเร็จ"].to_s.strip,
        buyer_username: values["ชื่อผู้ใช้ (ผู้ซื้อ)"].to_s.strip,
        ordered_at_raw: values["วันที่ทำการสั่งซื้อ"].to_s.strip,
        shipping_option: values["ตัวเลือกการจัดส่ง"].to_s.strip,
        shipping_method: values["วิธีการจัดส่ง"].to_s.strip,
        tracking_number: values["*หมายเลขติดตามพัสดุ"].to_s.strip,
        shipped_at_raw: values["เวลาส่งสินค้า"].to_s.strip,
        sku_code: values["เลขอ้างอิง SKU (SKU Reference No.)"].to_s.strip,
        quantity: normalize_qty(values["จำนวน"]),
        returned_quantity: values["จำนวนที่ส่งคืน"].to_i,
        raw_row: values
      }
    end

    def failed_delivery_row?(row)
      row[:external_order_id].present? &&
        row[:failed_delivery_status].present? &&
        row[:tracking_number].present? &&
        row[:sku_code].present?
    end

    def build_raw_failed_delivery(external_order_id, rows)
      first = rows.first

      {
        "external_order_id" => external_order_id,
        "order_status_raw" => first[:order_status_raw],
        "failed_delivery_status" => first[:failed_delivery_status],
        "tracking_number" => first[:tracking_number],
        "buyer_username" => first[:buyer_username],
        "shipping_option" => first[:shipping_option],
        "shipping_method" => first[:shipping_method],
        "ordered_at" => parse_time(first[:ordered_at_raw]),
        "shipped_at" => parse_time(first[:shipped_at_raw]),
        "rows" => rows.map { |row| serialize_row(row) },
        "lines" => build_lines(rows)
      }
    end

    def build_lines(rows)
      rows
        .group_by { |row| row[:sku_code].to_s.strip }
        .map do |sku_code, grouped_rows|
          {
            "sku_code_snapshot" => sku_code,
            "qty_returned" => grouped_rows.sum { |row| normalize_qty(row[:quantity]) },
            "raw_payload" => {
              "source" => "shopee_failed_delivery_import",
              "sku_code" => sku_code,
              "rows" => grouped_rows.map { |row| serialize_row(row) }
            }
          }
        end
    end

    def serialize_row(row)
      {
        "external_order_id" => row[:external_order_id],
        "order_status_raw" => row[:order_status_raw],
        "refund_return_status_raw" => row[:refund_return_status_raw],
        "failed_delivery_status" => row[:failed_delivery_status],
        "buyer_username" => row[:buyer_username],
        "tracking_number" => row[:tracking_number],
        "shipped_at_raw" => row[:shipped_at_raw],
        "sku_code" => row[:sku_code],
        "quantity" => normalize_qty(row[:quantity]),
        "returned_quantity" => row[:returned_quantity]
      }
    end

    def normalize_qty(value)
      qty = value.to_i
      qty.positive? ? qty : 1
    end

    def parse_time(value)
      return nil if value.blank?

      Time.find_zone!("Asia/Bangkok").parse(value.to_s)
    rescue
      nil
    end

    def build_error_summary(errors)
      return nil if errors.empty?

      lines = [ "Sample errors:" ]
      errors.first(20).each do |e|
        lines << "- #{e[:external_order_id]}: #{e[:err_class]} #{e[:err_message]}"
      end

      lines.join("\n")
    end

    def cell(row, idx, header_name)
      pos = idx.fetch(header_name)
      row[pos].to_s.strip
    end
  end
end

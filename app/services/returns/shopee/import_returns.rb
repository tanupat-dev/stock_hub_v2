# frozen_string_literal: true

require "roo"

module Returns
  module Shopee
    class ImportReturns
    REQUIRED_HEADERS = [
      "หมายเลขคำขอคืนเงิน/คืนสินค้า",
      "หมายเลขคำสั่งซื้อ",
      "เลข SKU",
      "จำนวนสินค้าคืน",
      "สถานะการคืนเงินหรือคืนสินค้า",
      "หมายเลขติดตามพัสดุสำหรับส่งคืน",
      "เวลายื่นคำขอคืนเงิน/คืนสินค้า",
      "ช่องทางการส่งสินค้าคืน",
      "สถานะการส่งสินค้าคืน",
      "เวลาที่จัดส่งสินค้าคืนสำเร็จ",
      "ชื่อผู้ใช้ (ผู้ซื้อ)"
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
        kind: "shopee_return_import",
        status: "processing",
        source_filename: @source_filename,
        started_at: Time.current
      )

      rows = load_rows!
      grouped = rows.group_by { |r| r[:external_return_id].to_s }

      success_returns = 0
      failed_returns = 0
      success_rows = 0
      failed_rows = 0
      errors = []

      grouped.each do |external_return_id, return_rows|
        begin
          raw_return = Returns::Shopee::Transformer.call(
            group_key: external_return_id,
            rows: return_rows
          )

          Returns::Shopee::Upsert.call!(
            shop: @shop,
            raw_return: raw_return
          )

          success_returns += 1
          success_rows += return_rows.size
        rescue => e
          failed_returns += 1
          failed_rows += return_rows.size

          errors << {
            external_return_id: external_return_id,
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
          grouped_returns: grouped.size,
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
        grouped_returns: grouped.size,
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
      workbook = open_workbook(@filepath)
      sheet = workbook.sheet(0)

      header = sheet.row(1).map { |v| v.to_s.strip }
      missing = REQUIRED_HEADERS - header
      raise "missing required headers: #{missing.join(', ')}" if missing.any?

      idx = header.each_with_index.to_h
      rows = []

      (2..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)

        external_return_id = cell(row, idx, "หมายเลขคำขอคืนเงิน/คืนสินค้า")
        next if external_return_id.blank?

        rows << {
          external_return_id: external_return_id,
          external_order_id: cell(row, idx, "หมายเลขคำสั่งซื้อ"),
          sku_code: cell(row, idx, "เลข SKU"),
          qty_returned: cell(row, idx, "จำนวนสินค้าคืน"),
          status_marketplace: cell(row, idx, "สถานะการคืนเงินหรือคืนสินค้า"),
          tracking_number: cell(row, idx, "หมายเลขติดตามพัสดุสำหรับส่งคืน"),
          requested_at_raw: cell(row, idx, "เวลายื่นคำขอคืนเงิน/คืนสินค้า"),
          return_carrier_method: cell(row, idx, "ช่องทางการส่งสินค้าคืน"),
          return_delivery_status: cell(row, idx, "สถานะการส่งสินค้าคืน"),
          returned_delivered_at_raw: cell(row, idx, "เวลาที่จัดส่งสินค้าคืนสำเร็จ"),
          buyer_username: cell(row, idx, "ชื่อผู้ใช้ (ผู้ซื้อ)")
        }
      end

      rows
    end

    def open_workbook(path)
      ext = File.extname(path).downcase

      if ext == ".xls"
        # 🔥 detect จริงก่อน
        first_bytes = File.binread(path, 4)

        if first_bytes.start_with?("PK")
          # จริงคือ xlsx
          Roo::Excelx.new(path)
        else
          Roo::Excel.new(path)
        end
      else
        Roo::Excelx.new(path)
      end
    end

    def build_error_summary(errors)
      return nil if errors.empty?

      lines = [ "Sample errors:" ]
      errors.first(10).each do |e|
        lines << "- #{e[:external_return_id]}: #{e[:err_class]} #{e[:err_message]}"
      end
      lines.join("\n")
    end

    def cell(row, idx, header_name)
      pos = idx.fetch(header_name)
      row[pos].to_s.strip
    end
    end
  end
end

# frozen_string_literal: true

require "rubyXL"

module Shopee
  class ExportStockExcel
    STOCK_COLUMN_INDEX = 8 # I column, zero-based
    SKU_COLUMN_INDEX = 5   # F column = เลข SKU

    def self.call!(shop:, template_path:, output_path:)
      new(shop:, template_path:, output_path:).call!
    end

    def initialize(shop:, template_path:, output_path:)
      @shop = shop
      @template_path = template_path
      @output_path = output_path
    end

    def call!
      batch = FileBatch.create!(
        channel: "shopee",
        shop: @shop,
        kind: "shopee_stock_export",
        status: "processing",
        source_filename: File.basename(@template_path),
        started_at: Time.current
      )

      workbook = RubyXL::Parser.parse(@template_path)
      sheet = workbook[0]

      row_entries = collect_row_entries(sheet)
      raise "invalid shopee stock template: no sku rows found" if row_entries.empty?

      mapping_sync_result =
        ::Shopee::SyncSkuMappingFromStockTemplate.call!(
          shop: @shop,
          row_entries: row_entries,
          dry_run: false
        )

      sku_codes = row_entries.map { |e| e[:sku_code] }.uniq
      skus_by_code = Sku.includes(:inventory_balance).where(code: sku_codes).index_by(&:code)

      total_rows = row_entries.size
      updated_rows = 0
      missing_rows = []

      row_entries.each do |entry|
        sku = skus_by_code[entry[:sku_code]]

        if sku.nil?
          missing_rows << {
            excel_row: entry[:excel_row],
            sku_code: entry[:sku_code]
          }
          next
        end

        stock_value = sku.online_available.to_i
        write_cell(sheet, entry[:row_idx], STOCK_COLUMN_INDEX, stock_value)
        updated_rows += 1
      end

      workbook.write(@output_path)

      batch.update!(
        total_rows: total_rows,
        success_rows: updated_rows,
        failed_rows: 0,
        meta: {
          output_path: @output_path,
          updated_rows: updated_rows,
          mapping_sync: mapping_sync_result,
          missing_sku_rows: missing_rows.size,
          missing_sku_codes: missing_rows.first(100)
        },
        error_summary: build_error_summary(missing_rows),
        status: "completed",
        finished_at: Time.current
      )

      {
        ok: true,
        batch_id: batch.id,
        total_rows: total_rows,
        updated_rows: updated_rows,
        missing_sku_rows: missing_rows.size,
        output_path: @output_path,
        mapping_sync: mapping_sync_result
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

    def collect_row_entries(sheet)
      out = []

      (1..sheet.sheet_data.size - 1).each do |row_idx|
        row = sheet[row_idx]
        next if row.nil?

        sku_code = normalize_sku_code(cell_value(row[SKU_COLUMN_INDEX]))
        next if sku_code.blank? || sku_code == "เลข SKU"

        out << {
          row_idx: row_idx,
          excel_row: row_idx + 1,
          sku_code: sku_code
        }
      end

      out
    end

    def normalize_sku_code(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def cell_value(cell)
      cell&.value
    end

    def write_cell(sheet, row_idx, col_idx, value)
      row = sheet[row_idx]

      if row && row[col_idx]
        cell = row[col_idx]
        cell.raw_value = value.to_s
        cell.datatype = nil
      else
        sheet.add_cell(row_idx, col_idx, value)
      end
    end

    def build_error_summary(missing_rows)
      return nil if missing_rows.empty?

      lines = [ "Missing SKU codes:" ]
      missing_rows.first(20).each do |row|
        lines << "- row #{row[:excel_row]}: #{row[:sku_code]}"
      end

      lines.join("\n")
    end
  end
end

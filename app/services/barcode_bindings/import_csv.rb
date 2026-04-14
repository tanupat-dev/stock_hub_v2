# frozen_string_literal: true

require "csv"
require "set"

module BarcodeBindings
  class ImportCsv
    REQUIRED_HEADERS = %w[sku barcode].freeze

    def self.call!(file:, force: false)
      new(file:, force: force).call
    end

    def initialize(file:, force:)
      @file = file
      @force = force
    end

    def call
      validate_file!

      total_rows = 0
      success_rows = 0
      failed_rows = 0
      blank_rows = 0
      duplicate_rows_in_file = 0

      success_samples = []
      error_samples = []
      duplicate_samples = []
      seen_pairs = Set.new

      table = read_csv_table
      validate_headers!(table.headers)

      table.each do |row|
        total_rows += 1

        data = normalized_row(row)
        sku_code = normalize_value(data["sku"])
        barcode = normalize_barcode(data["barcode"])

        if sku_code.blank? && barcode.blank?
          blank_rows += 1
          next
        end

        pair_key = "#{sku_code}||#{barcode}"
        if seen_pairs.include?(pair_key)
          duplicate_rows_in_file += 1
          duplicate_samples << {
            row: total_rows + 1,
            sku: sku_code,
            barcode: barcode
          } if duplicate_samples.size < 20
          next
        end
        seen_pairs << pair_key

        if sku_code.blank?
          failed_rows += 1
          error_samples << {
            row: total_rows + 1,
            sku: sku_code,
            barcode: barcode,
            error: "sku is blank"
          } if error_samples.size < 50
          next
        end

        if barcode.blank?
          failed_rows += 1
          error_samples << {
            row: total_rows + 1,
            sku: sku_code,
            barcode: barcode,
            error: "barcode is blank"
          } if error_samples.size < 50
          next
        end

        sku = Sku.find_by(code: sku_code)
        unless sku
          failed_rows += 1
          error_samples << {
            row: total_rows + 1,
            sku: sku_code,
            barcode: barcode,
            error: "SKU not found"
          } if error_samples.size < 50
          next
        end

        result = Inventory::BindBarcode.call!(
          sku: sku,
          barcode: barcode,
          force: @force,
          meta: {
            source: "ops_barcode_bindings_import",
            filename: @file.original_filename
          }
        )

        success_rows += 1
        success_samples << {
          row: total_rows + 1,
          sku: sku_code,
          barcode: barcode,
          result: result
        } if success_samples.size < 20
      rescue Inventory::BindBarcode::SkuRequired,
             Inventory::BindBarcode::BarcodeBlank,
             Inventory::BindBarcode::BarcodeAlreadyAssigned,
             Inventory::BindBarcode::BarcodeAlreadyBoundOnSku => e
        failed_rows += 1
        error_samples << {
          row: total_rows + 1,
          sku: sku_code,
          barcode: barcode,
          error: e.message
        } if error_samples.size < 50
      end

      {
        total_rows: total_rows,
        success_rows: success_rows,
        failed_rows: failed_rows,
        blank_rows: blank_rows,
        duplicate_rows_in_file: duplicate_rows_in_file,
        force: @force,
        success_samples: success_samples,
        duplicate_samples: duplicate_samples,
        error_samples: error_samples
      }
    end

    private

    def validate_file!
      filename = @file.original_filename.to_s
      ext = File.extname(filename).downcase
      content_type = @file.content_type.to_s

      raise ArgumentError, "CSV file required" unless ext == ".csv"
      raise ArgumentError, "Empty file" if @file.size.to_i <= 0

      allowed_types = [ "text/csv", "application/vnd.ms-excel", "" ]
      return if allowed_types.include?(content_type)

      raise ArgumentError, "Invalid file type"
    end

    def read_csv_table
      raw = File.binread(@file.path)

      text = raw
        .force_encoding("UTF-8")
        .sub(/\A\xEF\xBB\xBF/, "")
        .gsub("\r\n", "\n")
        .gsub("\r", "\n")

      CSV.parse(text, headers: true, liberal_parsing: true)
    end

    def validate_headers!(headers)
      normalized = headers.compact.map { |h| normalize_header(h) }
      missing = REQUIRED_HEADERS - normalized
      return if missing.empty?

      raise ArgumentError, "Missing required columns: #{missing.join(', ')}"
    end

    def normalized_row(row)
      row.to_h.each_with_object({}) do |(key, value), acc|
        acc[normalize_header(key)] = value
      end
    end

    def normalize_header(value)
      value.to_s
           .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
           .sub(/\A\uFEFF/, "")
           .strip
           .downcase
    end

    def normalize_value(value)
      v = value.to_s.strip
      v.present? ? v : nil
    end

    def normalize_barcode(value)
      v = value.to_s.gsub(/\s+/, "").strip
      v.present? ? v : nil
    end
  end
end

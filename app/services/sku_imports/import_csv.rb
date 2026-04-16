# frozen_string_literal: true

require "csv"
require "set"

module SkuImports
  class ImportCsv
    REQUIRED_HEADERS = %w[sku brand model color size].freeze
    OPTIONAL_HEADERS = %w[buffer_quantity on_hand].freeze

    def self.call!(file:, dry_run: false, stock_mode: "skip")
      new(file, dry_run, stock_mode).call
    end

    def initialize(file, dry_run, stock_mode)
      @file = file
      @dry_run = dry_run
      @stock_mode = stock_mode
    end

    def call
      validate_file!

      now = Time.current
      total_rows = 0
      blank_rows = 0
      duplicate_rows_in_file = 0
      invalid_format_rows = 0
      upsert_rows = []
      invalid_samples = []
      duplicate_samples = []
      seen_codes = {}

      table = read_csv_table
      validate_headers!(table.headers)

      table.each do |row|
        total_rows += 1
        data = normalized_row(row)

        raw_code = data["sku"]
        code = normalize_sku(raw_code)

        if code.blank?
          blank_rows += 1
          next
        end

        sku_parts = parse_sku_parts(code)
        unless sku_parts
          invalid_format_rows += 1
          invalid_samples << {
            row: total_rows + 1,
            code: code,
            error: "sku must be brand.model.color.size"
          } if invalid_samples.size < 20
          next
        end

        unless matches_row_columns?(sku_parts, data)
          invalid_format_rows += 1
          invalid_samples << {
            row: total_rows + 1,
            code: code,
            error: "sku does not match brand/model/color/size columns"
          } if invalid_samples.size < 20
          next
        end

        if seen_codes[code]
          duplicate_rows_in_file += 1
          duplicate_samples << {
            row: total_rows + 1,
            code: code
          } if duplicate_samples.size < 20
          next
        end
        seen_codes[code] = true

        attrs = {
          code: code,
          brand: presence_or_nil(data["brand"]),
          model: sku_parts[:model],
          color: sku_parts[:color],
          size: sku_parts[:size],
          created_at: now,
          updated_at: now
        }

        buffer_raw = data["buffer_quantity"]
        attrs[:buffer_quantity] = Integer(buffer_raw) if presence_or_nil(buffer_raw).present?

        on_hand =
          if presence_or_nil(data["on_hand"]).present?
            Integer(data["on_hand"])
          else
            nil
          end

        upsert_rows << attrs.merge(__on_hand: on_hand)
      rescue ArgumentError
        invalid_format_rows += 1
        invalid_samples << {
          row: total_rows + 1,
          code: code,
          error: "invalid buffer_quantity or on_hand"
        } if invalid_samples.size < 20
      end

      if upsert_rows.empty?
        result = {
          dry_run: @dry_run,
          stock_mode: @stock_mode,
          total_rows: total_rows,
          upsert_rows: 0,
          blank_rows: blank_rows,
          duplicate_rows_in_file: duplicate_rows_in_file,
          duplicate_samples: duplicate_samples,
          invalid_format_rows: invalid_format_rows,
          created_estimate: 0,
          existing_estimate: 0,
          invalid_samples: invalid_samples
        }

        log_result(result)
        return result
      end

      existing_codes = Sku.where(code: upsert_rows.map { |r| r[:code] }).pluck(:code).to_set
      created_estimate = upsert_rows.count { |r| !existing_codes.include?(r[:code]) }
      existing_estimate = upsert_rows.size - created_estimate

      db_rows = upsert_rows.map { |r| r.except(:__on_hand) }

      result =
        if @dry_run
          []
        else
          Sku.upsert_all(
            db_rows,
            unique_by: :index_skus_on_code,
            update_only: %i[brand model color size buffer_quantity updated_at],
            record_timestamps: false
          )
        end

      stock_result =
        if @stock_mode == "skip"
          {
            stock_updated: 0,
            stock_failed: 0,
            stock_failed_samples: [],
            stock_preview: nil
          }
        elsif @dry_run
          simulate_stock_updates!(upsert_rows)
        else
          apply_stock_updates!(upsert_rows)
        end

      payload = {
        dry_run: @dry_run,
        stock_mode: @stock_mode,
        total_rows: total_rows,
        upsert_rows: upsert_rows.size,
        blank_rows: blank_rows,
        duplicate_rows_in_file: duplicate_rows_in_file,
        duplicate_samples: duplicate_samples,
        invalid_format_rows: invalid_format_rows,
        created_estimate: created_estimate,
        existing_estimate: existing_estimate,
        invalid_samples: invalid_samples,
        db_result: result.to_a,
        **stock_result
      }

      log_result(payload)
      payload
    end

    private

    def simulate_stock_updates!(rows)
      will_update = 0
      will_noop = 0
      will_fail = 0

      failed_samples = []

      rows.each_with_index do |row, idx|
        on_hand = row[:__on_hand]
        next if on_hand.nil?

        sku_code = row[:code]

        sku = Sku.find_by(code: sku_code)

        unless sku
          will_fail += 1
          failed_samples << {
            sku: sku_code,
            error: "sku not found"
          } if failed_samples.size < 20
          next
        end

        if on_hand < 0
          will_fail += 1
          failed_samples << {
            sku: sku_code,
            error: "on_hand must be >= 0"
          } if failed_samples.size < 20
          next
        end

        balance = sku.inventory_balance
        current_on_hand = balance&.on_hand.to_i

        if on_hand == current_on_hand
          will_noop += 1
        else
          will_update += 1
        end
      end

      {
        stock_updated: 0,
        stock_failed: will_fail,
        stock_failed_samples: failed_samples,
        stock_preview: {
          will_update: will_update,
          will_noop: will_noop,
          will_fail: will_fail
        }
      }
    end

    def apply_stock_updates!(rows)
      updated = 0
      failed = 0
      failed_samples = []

      rows.each_with_index do |row, idx|
        on_hand = row[:__on_hand]
        next if on_hand.nil?

        sku_code = row[:code]

        begin
          sku = Sku.find_by(code: sku_code)
          next unless sku

          if on_hand < 0
            failed += 1
            failed_samples << {
              sku: sku_code,
              error: "on_hand must be >= 0"
            } if failed_samples.size < 20
            next
          end

          idempotency_key = "sku_import:set_exact:#{sku.code}:#{on_hand}"

          result = Inventory::Adjust.call!(
            sku: sku,
            set_to: on_hand,
            idempotency_key: idempotency_key,
            meta: {
              source: "sku_import",
              import_type: "set_exact",
              row_index: idx
            }
          )

          updated += 1 if result == :adjusted
        rescue => e
          failed += 1
          failed_samples << {
            sku: sku_code,
            error: e.message
          } if failed_samples.size < 20
        end
      end

      {
        stock_updated: updated,
        stock_failed: failed,
        stock_failed_samples: failed_samples
      }
    end

    def validate_file!
      filename = @file.original_filename.to_s
      ext = File.extname(filename).downcase
      content_type = @file.content_type.to_s

      raise ArgumentError, "CSV file required" unless ext == ".csv"
      raise ArgumentError, "Empty file" if @file.size.to_i <= 0

      allowed_types = [
        "text/csv",
        "application/vnd.ms-excel",
        "application/octet-stream",
        ""
      ]
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

    def normalize_header(value)
      value.to_s
           .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
           .sub(/\A\uFEFF/, "")
           .strip
           .downcase
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

    def normalize_sku(code)
      code.to_s.strip.gsub(/\s*\.\s*/, ".")
    end

    def parse_sku_parts(code)
      parts = code.to_s.split(".")
      return nil unless parts.size == 4
      return nil unless parts.all?(&:present?)

      {
        brand: parts[0],
        model: parts[1],
        color: parts[2],
        size: parts[3]
      }
    end

    def matches_row_columns?(sku_parts, row)
      return false if sku_parts.nil?

      model = presence_or_nil(row["model"])
      color = presence_or_nil(row["color"])
      size = presence_or_nil(row["size"])

      sku_parts[:model] == model &&
        sku_parts[:color] == color &&
        sku_parts[:size] == size
    end

    def presence_or_nil(value)
      v = value.to_s.strip
      v.present? ? v : nil
    end

    def log_result(payload)
      Rails.logger.info(
        {
          event: "ops.sku_import.completed",
          filename: @file.original_filename,
          **payload.except(:db_result)
        }.to_json
      )
    end
  end
end

# frozen_string_literal: true

module Shopee
  class SyncSkuMappingFromStockTemplate
    def self.call!(shop:, row_entries:, dry_run: false)
      new(shop:, row_entries:, dry_run:).call!
    end

    def initialize(shop:, row_entries:, dry_run:)
      @shop = shop
      @row_entries = Array(row_entries)
      @dry_run = dry_run

      raise ArgumentError, "shop is required" if @shop.nil?
      raise ArgumentError, "shop #{@shop.id} is not shopee" unless @shop.channel == "shopee"
    end

    def call!
      desired_rows, duplicate_skus = build_desired_rows

      stats = {
        ok: true,
        shop_id: @shop.id,
        shop_code: @shop.shop_code,
        channel: @shop.channel,
        dry_run: @dry_run,
        source_rows: @row_entries.size,
        unique_sku_codes: desired_rows.size,
        duplicate_sku_codes_count: duplicate_skus.size,
        duplicate_sku_codes_sample: duplicate_skus.first(50),
        missing_sku_count: 0,
        missing_sku_sample: [],
        upserted_mappings: 0,
        deleted_mappings: 0
      }

      return stats.merge(note: "no_candidate_rows") if desired_rows.empty?

      existing_skus = Sku.where(code: desired_rows.map { |r| r[:external_sku] }).pluck(:code, :id).to_h

      upsert_rows = []
      missing = []

      desired_rows.each do |row|
        sku_id = existing_skus[row[:external_sku]]
        if sku_id.nil?
          missing << row[:external_sku]
          next
        end

        upsert_rows << row.merge(sku_id: sku_id)
      end

      stats[:missing_sku_count] = missing.size
      stats[:missing_sku_sample] = missing.first(100)

      unless @dry_run
        if upsert_rows.any?
          now = Time.current

          rows = upsert_rows.map do |row|
            {
              channel: @shop.channel,
              shop_id: @shop.id,
              external_sku: row[:external_sku],
              external_variant_id: nil,
              sku_id: row[:sku_id],
              created_at: now,
              updated_at: now
            }
          end

          SkuMapping.upsert_all(
            rows,
            unique_by: :uniq_sku_mappings,
            record_timestamps: false,
            update_only: %i[sku_id external_variant_id updated_at]
          )

          stats[:upserted_mappings] = rows.size
        end

        keep_external_skus = upsert_rows.map { |r| r[:external_sku] }.uniq

        delete_scope = SkuMapping.where(channel: @shop.channel, shop_id: @shop.id)
        delete_scope = delete_scope.where.not(external_sku: keep_external_skus) if keep_external_skus.any?

        stats[:deleted_mappings] = delete_scope.delete_all
      end

      Rails.logger.info(
        {
          event: "shopee.sync_sku_mapping_from_stock_template.done",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          dry_run: @dry_run,
          source_rows: stats[:source_rows],
          unique_sku_codes: stats[:unique_sku_codes],
          duplicate_sku_codes_count: stats[:duplicate_sku_codes_count],
          missing_sku_count: stats[:missing_sku_count],
          upserted_mappings: stats[:upserted_mappings],
          deleted_mappings: stats[:deleted_mappings]
        }.to_json
      )

      stats
    rescue => e
      Rails.logger.error(
        {
          event: "shopee.sync_sku_mapping_from_stock_template.fail",
          shop_id: @shop&.id,
          shop_code: @shop&.shop_code,
          dry_run: @dry_run,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
      raise
    end

    private

    def build_desired_rows
      seen = {}
      duplicate_skus = []

      desired_rows =
        @row_entries.each_with_object([]) do |entry, out|
          external_sku = normalize_sku_code(entry[:sku_code])
          next if external_sku.blank?

          if seen.key?(external_sku)
            duplicate_skus << external_sku unless duplicate_skus.include?(external_sku)
            next
          end

          seen[external_sku] = true

          out << {
            external_sku: external_sku,
            excel_row: entry[:excel_row]
          }
        end

      [ desired_rows, duplicate_skus ]
    end

    def normalize_sku_code(value)
      value.to_s.gsub(/\s+/, " ").strip.presence
    end
  end
end

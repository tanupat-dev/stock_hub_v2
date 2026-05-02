# frozen_string_literal: true

module Skus
  class ArchiveUnmapped
    DEFAULT_LIMIT = 100

    def self.call!(dry_run: true, limit: DEFAULT_LIMIT)
      new(dry_run: dry_run, limit: limit).call!
    end

    def initialize(dry_run:, limit:)
      @dry_run = dry_run
      @limit = limit.to_i > 0 ? limit.to_i : DEFAULT_LIMIT

      @result = {
        dry_run: @dry_run,
        scanned: 0,
        unmapped: 0,
        archived: 0,
        skipped: 0,
        rows: []
      }
    end

    def call!
      log(:start)

      Sku
        .left_joins(:sku_mappings)
        .where(sku_mappings: { id: nil })
        .where(active: true)
        .order(:id)
        .limit(@limit)
        .find_each(batch_size: 50) do |sku|
        @result[:scanned] += 1
        @result[:unmapped] += 1

        if @dry_run
          record(sku, :dry_run)
          next
        end

        archive!(sku)
      end

      log(:finish)
      @result
    end

    private

    def archive!(sku)
      sku.update!(
        active: false,
        archived_at: Time.current
      )

      @result[:archived] += 1
      record(sku, :archived)

      log(:archived, sku_id: sku.id, code: sku.code)
    rescue => e
      @result[:skipped] += 1
      record(sku, :failed)

      log(:failed, sku_id: sku.id, error: e.message)
    end

    def record(sku, status)
      @result[:rows] << {
        sku_id: sku.id,
        code: sku.code,
        status: status
      }
    end

    def log(event, extra = {})
      Rails.logger.info(
        {
          event: "skus.archive_unmapped.#{event}",
          **@result.except(:rows),
          **extra
        }.to_json
      )
    end
  end
end

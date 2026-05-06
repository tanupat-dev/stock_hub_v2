# frozen_string_literal: true

class SkuImportJob < ApplicationJob
  queue_as :imports

  BATCH_SIZE = 200

  def perform(batch_id, rows)
    batch = SkuImportBatch.find(batch_id)

    batch.update!(
      status: "processing",
      started_at: Time.current,
      error_message: nil
    )

    now = Time.current

    total_rows = 0
    upsert_rows_count = 0
    stock_updated = 0
    stock_failed = 0
    stock_failed_samples = []

    rows.each_slice(BATCH_SIZE) do |chunk|
      stats = process_chunk(chunk, now, batch)

      total_rows += stats[:total_rows]
      upsert_rows_count += stats[:upsert_rows]
      stock_updated += stats[:stock_updated]
      stock_failed += stats[:stock_failed]

      stock_failed_samples.concat(stats[:stock_failed_samples])
      stock_failed_samples = stock_failed_samples.first(20)

      batch.update_columns(
        total_rows: total_rows,
        upsert_rows: upsert_rows_count,
        stock_updated: stock_updated,
        stock_failed: stock_failed,
        result: { stock_failed_samples: stock_failed_samples },
        updated_at: Time.current
      )
    end

    trigger_bulk_sync if batch.stock_mode != "skip" && !batch.dry_run

    batch.update!(
      status: "completed",
      completed_at: Time.current
    )
  rescue => e
    batch&.update!(
      status: "failed",
      error_message: "#{e.class}: #{e.message}",
      completed_at: Time.current
    ) rescue nil

    Rails.logger.error(
      {
        event: "sku_import_job.failed",
        batch_id: batch_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  end

  private

  def process_chunk(rows, now, batch)
    upsert_rows = []
    stock_rows = []

    rows.each do |row|
      code = normalize_sku(row["sku"])
      next if code.blank?

      upsert_rows << build_sku_attrs(row, code, now)

      stock_rows << {
        code: code,
        on_hand: parse_non_negative_integer(row["on_hand"])
      }
    end

    unless batch.dry_run || upsert_rows.empty?
      Sku.upsert_all(
        upsert_rows,
        unique_by: :index_skus_on_code,
        update_only: %i[brand model color size buffer_quantity updated_at],
        record_timestamps: false
      )
    end

    skus = Sku.where(code: upsert_rows.map { |r| r[:code] })
    ensure_identity!(skus) unless batch.dry_run

    if batch.stock_mode == "skip"
      return {
        total_rows: rows.size,
        upsert_rows: upsert_rows.size,
        stock_updated: 0,
        stock_failed: 0,
        stock_failed_samples: []
      }
    end

    stock_stats = apply_stock_rows(stock_rows, batch)

    {
      total_rows: rows.size,
      upsert_rows: upsert_rows.size,
      **stock_stats
    }
  end

  def ensure_identity!(skus)
    skus.where(stock_identity_id: nil).find_each do |sku|
      identity = StockIdentity.create!(code: "sku:#{sku.code}")

      sku.update_columns(stock_identity_id: identity.id)

      InventoryBalance.create!(
        stock_identity_id: identity.id,
        sku_id: sku.id,
        on_hand: 0,
        reserved: 0
      )
    end
  end

  def apply_stock_rows(stock_rows, batch)
    return empty_stock_stats if stock_rows.empty?

    sku_map = Sku
      .where(code: stock_rows.map { |r| r[:code] })
      .includes(:inventory_balance)
      .index_by(&:code)

    updated = 0
    failed = 0
    failed_samples = []

    stock_rows.each do |row|
      sku = sku_map[row[:code]]
      on_hand = row[:on_hand]

      next if sku.nil? || on_hand.nil?

      begin
        current = sku.inventory_balance&.on_hand.to_i
        next if current == on_hand

        next if batch.dry_run

        Inventory::Adjust.call!(
          sku: sku,
          set_to: on_hand,
          idempotency_key: "sku_import:batch=#{batch.id}:sku=#{sku.code}:#{on_hand}",
          meta: { source: "sku_import", batch_id: batch.id }
        )

        updated += 1
      rescue => e
        failed += 1
        failed_samples << {
          sku: row[:code],
          error: "#{e.class}: #{e.message}"
        } if failed_samples.size < 20
      end
    end

    {
      stock_updated: updated,
      stock_failed: failed,
      stock_failed_samples: failed_samples
    }
  end

  def empty_stock_stats
    {
      stock_updated: 0,
      stock_failed: 0,
      stock_failed_samples: []
    }
  end

  def trigger_bulk_sync
    CleanupStaleJobsJob.enqueue_once!(reason: "sku_import")
    SystemAutoHealJob.enqueue_once!
  rescue => e
    Rails.logger.warn(
      {
        event: "sku_import.bulk_sync_failed",
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end

  def build_sku_attrs(row, code, now)
    {
      code: code,
      brand: presence_or_nil(row["brand"]),
      model: presence_or_nil(row["model"]),
      color: presence_or_nil(row["color"]),
      size: presence_or_nil(row["size"]),
      created_at: now,
      updated_at: now
    }.tap do |attrs|
      buffer = parse_non_negative_integer(row["buffer_quantity"])
      attrs[:buffer_quantity] = buffer unless buffer.nil?
    end
  end

  def normalize_sku(value)
    value.to_s.strip.gsub(/\s*\.\s*/, ".")
  end

  def presence_or_nil(value)
    v = value.to_s.strip
    v.present? ? v : nil
  end

  def parse_non_negative_integer(value)
    raw = presence_or_nil(value)
    return nil if raw.nil?

    i = Integer(raw)
    i >= 0 ? i : nil
  rescue
    nil
  end
end

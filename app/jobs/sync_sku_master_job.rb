# frozen_string_literal: true

class SyncSkuMasterJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  BATCH_SIZE = 500

  def perform(
    shop_id,
    enqueue_sync_stock: false,
    dry_run: false,
    cursor_id: nil,
    scanned_total: 0
  )
    started_at = Time.current
    shop = Shop.find(shop_id)

    unless shop.active?
      return {
        ok: true,
        skipped: true,
        reason: "inactive_shop",
        shop_id: shop.id
      }
    end

    unless supported_channel?(shop.channel)
      return {
        ok: true,
        skipped: true,
        reason: "unsupported_channel",
        shop_id: shop.id,
        channel: shop.channel
      }
    end

    scope =
      MarketplaceItem
        .where(shop_id: shop.id)
        .where("id > ?", cursor_id.to_i)
        .order(:id)
        .limit(BATCH_SIZE)

    items = scope.to_a

    if items.empty?
      Rails.logger.info(
        {
          event: "sync_sku_master_job.done",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          scanned_total: scanned_total.to_i,
          dry_run: dry_run,
          enqueue_sync_stock: enqueue_sync_stock,
          duration_ms: ((Time.current - started_at) * 1000).round
        }.to_json
      )

      return {
        ok: true,
        shop_id: shop.id,
        channel: shop.channel,
        scanned_total: scanned_total.to_i,
        done: true
      }
    end

    rows = items.map do |item|
      {
        external_sku: item.external_sku.to_s.strip.presence,
        external_variant_id: item.external_variant_id.to_s.strip.presence,
        status: item.status.to_s.strip.presence
      }
    end

    result = Catalog::SyncSkuMasterFromCatalog.call!(
      shop: shop,
      items: rows,
      match_by: :code,
      enqueue_sync_stock: enqueue_sync_stock,
      dry_run: dry_run
    )

    next_cursor_id = items.last.id
    next_scanned_total = scanned_total.to_i + items.size

    Rails.logger.info(
      {
        event: "sync_sku_master_job.batch_done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        cursor_id: cursor_id,
        next_cursor_id: next_cursor_id,
        batch_size: items.size,
        scanned_total: next_scanned_total,
        dry_run: dry_run,
        enqueue_sync_stock: enqueue_sync_stock,
        result: result,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    self.class.set(wait: 3.seconds).perform_later(
      shop.id,
      enqueue_sync_stock: enqueue_sync_stock,
      dry_run: dry_run,
      cursor_id: next_cursor_id,
      scanned_total: next_scanned_total
    )

    {
      ok: true,
      shop_id: shop.id,
      channel: shop.channel,
      batch_size: items.size,
      scanned_total: next_scanned_total,
      next_cursor_id: next_cursor_id,
      enqueued_next_batch: true
    }
  rescue => e
    Rails.logger.error(
      {
        event: "sync_sku_master_job.fail",
        shop_id: shop_id,
        cursor_id: cursor_id,
        scanned_total: scanned_total,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  ensure
    items = nil
    rows = nil
  end

  private

  def supported_channel?(channel)
    %w[tiktok lazada shopee].include?(channel)
  end
end

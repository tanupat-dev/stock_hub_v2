# frozen_string_literal: true

class PollTiktokAllShopsCatalogJob < ApplicationJob
  queue_as :default

  def perform(
    enqueue_sync_stock: true,
    enqueue_sync_sku_master: true,
    dry_run: false,
    resume: true,
    max_pages: 200,
    page_size: 50
  )
    started_at = Time.current
    total = 0
    enqueued = 0
    skipped = 0
    errors = 0

    Shop.where(active: true, channel: "tiktok").find_each do |shop|
      total += 1

      if shop.tiktok_credential_id.blank? || shop.shop_cipher.blank?
        skipped += 1
        Rails.logger.info(
          {
            event: "poll.tiktok.all_shops_catalog.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            skip_reason: "shop_not_ready"
          }.to_json
        )
        next
      end

      begin
        PollCatalogJob.perform_later(
          shop.id,
          enqueue_sync_stock: enqueue_sync_stock,
          enqueue_sync_sku_master: enqueue_sync_sku_master,
          dry_run: dry_run,
          resume: resume,
          max_pages: max_pages,
          page_size: page_size
        )
        enqueued += 1
      rescue => e
        errors += 1
        Rails.logger.error(
          {
            event: "poll.tiktok.all_shops_catalog.enqueue_fail",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    payload = {
      event: "poll.tiktok.all_shops_catalog.done",
      total_shops: total,
      enqueued: enqueued,
      skipped: skipped,
      errors: errors,
      duration_ms: ((Time.current - started_at) * 1000).round
    }

    if errors.positive?
      Rails.logger.error(payload.to_json)
    else
      Rails.logger.info(payload.to_json)
    end

    {
      ok: errors == 0,
      total_shops: total,
      enqueued: enqueued,
      skipped: skipped,
      errors: errors
    }
  end
end

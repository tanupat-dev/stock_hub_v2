# frozen_string_literal: true

class PollLazadaAllShopsCatalogJob < ApplicationJob
  queue_as :default

  def perform(update_after: nil, filter: "all", limit: 20, max_pages: 200, full: false)
    started_at = Time.current
    total = 0
    enqueued = 0
    skipped = 0
    errors = 0

    Shop.where(active: true, channel: "lazada").find_each do |shop|
      total += 1

      if shop.lazada_credential.blank?
        skipped += 1
        Rails.logger.info(
          {
            event: "poll.lazada.all_shops_catalog.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            skip_reason: "missing_lazada_credential"
          }.to_json
        )
        next
      end

      if shop.lazada_credential.lazada_app.blank? && shop.lazada_app_id.blank?
        skipped += 1
        Rails.logger.info(
          {
            event: "poll.lazada.all_shops_catalog.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            skip_reason: "missing_lazada_app"
          }.to_json
        )
        next
      end

      begin
        PollLazadaCatalogJob.perform_later(
          shop.id,
          update_after: update_after,
          filter: filter,
          limit: limit,
          max_pages: max_pages,
          full: full
        )
        enqueued += 1
      rescue => e
        errors += 1
        Rails.logger.error(
          {
            event: "poll.lazada.all_shops_catalog.enqueue_fail",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    payload = {
      event: "poll.lazada.all_shops_catalog.done",
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

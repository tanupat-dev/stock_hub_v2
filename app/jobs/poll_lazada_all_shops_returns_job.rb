# frozen_string_literal: true

class PollLazadaAllShopsReturnsJob < ApplicationJob
  queue_as :poll_orders

  def perform
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
            event: "poll.lazada.all_shops_returns.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            channel: shop.channel,
            skip_reason: "missing_lazada_credential"
          }.to_json
        )
        next
      end

      if shop.lazada_credential.lazada_app.blank?
        skipped += 1
        Rails.logger.info(
          {
            event: "poll.lazada.all_shops_returns.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            channel: shop.channel,
            skip_reason: "missing_lazada_app"
          }.to_json
        )
        next
      end

      begin
        PollLazadaReturnsJob.perform_later(shop.id)
        enqueued += 1
      rescue => e
        errors += 1
        Rails.logger.error(
          {
            event: "poll.lazada.all_shops_returns.enqueue_fail",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            channel: shop.channel,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    Rails.logger.info(
      {
        event: "poll.lazada.all_shops_returns.done",
        total_shops: total,
        enqueued: enqueued,
        skipped: skipped,
        errors: errors,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: errors == 0,
      total_shops: total,
      enqueued: enqueued,
      skipped: skipped,
      errors: errors
    }
  rescue => e
    Rails.logger.error(
      {
        event: "poll.lazada.all_shops_returns.fail",
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
    raise
  end
end

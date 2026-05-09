# frozen_string_literal: true

class PollTiktokAllShopsDeliveryFailuresJob < ApplicationJob
  queue_as :poll_orders

  def perform(
    limit: PollTiktokDeliveryFailuresJob::DEFAULT_LIMIT,
    max_age_days: PollTiktokDeliveryFailuresJob::DEFAULT_MAX_AGE_DAYS,
    order_direction: PollTiktokDeliveryFailuresJob::DEFAULT_ORDER_DIRECTION
  )
    started_at = Time.current
    total = 0
    enqueued = 0
    skipped = 0
    errors = 0

    Shop.where(active: true, channel: "tiktok").find_each do |shop|
      total += 1

      if shop.tiktok_credential_id.nil? || shop.shop_cipher.blank?
        skipped += 1

        Rails.logger.info(
          {
            event: "poll.tiktok.all_shops_delivery_failures.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            skip_reason: "shop_not_ready"
          }.to_json
        )

        next
      end

      begin
        PollTiktokDeliveryFailuresJob.perform_later(
          shop.id,
          limit: limit,
          max_age_days: max_age_days,
          order_direction: order_direction
        )

        enqueued += 1
      rescue => e
        errors += 1

        Rails.logger.error(
          {
            event: "poll.tiktok.all_shops_delivery_failures.enqueue_fail",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    Rails.logger.info(
      {
        event: "poll.tiktok.all_shops_delivery_failures.done",
        total_shops: total,
        enqueued: enqueued,
        skipped: skipped,
        errors: errors,
        limit: limit,
        max_age_days: max_age_days,
        order_direction: order_direction,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: errors.zero?,
      total_shops: total,
      enqueued: enqueued,
      skipped: skipped,
      errors: errors,
      order_direction: order_direction
    }
  rescue => e
    Rails.logger.error(
      {
        event: "poll.tiktok.all_shops_delivery_failures.fail",
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  end
end

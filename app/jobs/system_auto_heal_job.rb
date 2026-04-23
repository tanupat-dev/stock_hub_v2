# frozen_string_literal: true

class SystemAutoHealJob < ApplicationJob
  queue_as :default

  SHOP_WINDOW = 2.minutes
  GLOBAL_WINDOW = 5.minutes

  class << self
    def enqueue_once!(shop_id = nil)
      return :skipped if recently_enqueued?(shop_id)

      perform_later(shop_id)
      mark_enqueued!(shop_id)
      :enqueued
    end

    private

    def recently_enqueued?(shop_id)
      ts = Rails.cache.read(cache_key(shop_id))
      ts.present? && ts > window_for(shop_id).ago
    end

    def mark_enqueued!(shop_id)
      Rails.cache.write(
        cache_key(shop_id),
        Time.current,
        expires_in: window_for(shop_id)
      )
    end

    def cache_key(shop_id)
      if shop_id.present?
        "system_auto_heal_job:shop:#{shop_id}"
      else
        "system_auto_heal_job:global"
      end
    end

    def window_for(shop_id)
      shop_id.present? ? SHOP_WINDOW : GLOBAL_WINDOW
    end
  end

  def perform(shop_id = nil)
    CleanupStaleJobsJob.perform_now

    if shop_id.present?
      InventoryReconcileJob.perform_now(
        shop_id,
        fresh_within: 6.hours,
        push_limit: 100
      )

      Rails.logger.info(
        {
          event: "system_auto_heal_job.shop_done",
          shop_id: shop_id
        }.to_json
      )

      :shop_healed
    else
      InventoryReconcileAllShopsJob.perform_now(
        fresh_within: 6.hours,
        push_limit: 100
      )

      Rails.logger.info(
        {
          event: "system_auto_heal_job.global_done"
        }.to_json
      )

      :global_healed
    end
  rescue => e
    Rails.logger.error(
      {
        event: "system_auto_heal_job.fail",
        shop_id: shop_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
    raise
  end
end

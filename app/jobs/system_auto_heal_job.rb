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
    cleanup_enqueued = enqueue_cleanup_stale_jobs!
    reconcile_enqueued = enqueue_reconcile!(shop_id)

    Rails.logger.info(
      {
        event: "system_auto_heal_job.enqueued",
        mode: shop_id.present? ? "shop" : "global",
        shop_id: shop_id,
        cleanup_stale_jobs: cleanup_enqueued,
        reconcile: reconcile_enqueued
      }.to_json
    )

    shop_id.present? ? :shop_heal_enqueued : :global_heal_enqueued
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

  private

  def enqueue_cleanup_stale_jobs!
    CleanupStaleJobsJob.perform_later
    true
  end

  def enqueue_reconcile!(shop_id)
    if shop_id.present?
      InventoryReconcileJob.perform_later(
        shop_id,
        fresh_within: 6.hours,
        push_limit: 100
      )
      :shop
    else
      InventoryReconcileAllShopsJob.perform_later(
        fresh_within: 6.hours,
        push_limit: 100
      )
      :all_shops
    end
  end
end

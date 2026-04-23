# frozen_string_literal: true

class SystemAutoHealJob < ApplicationJob
  queue_as :default

  SHOP_HEAL_DEBOUNCE = 2.minutes
  GLOBAL_HEAL_DEBOUNCE = 5.minutes

  def perform(shop_id = nil)
    CleanupStaleJobsJob.perform_now

    if shop_id.present?
      return :shop_heal_skipped if recently_healed_shop?(shop_id)

      mark_shop_healed!(shop_id)
      InventoryReconcileJob.perform_now(shop_id, fresh_within: 6.hours, push_limit: 100)

      Rails.logger.info(
        {
          event: "system_auto_heal_job.shop_done",
          shop_id: shop_id
        }.to_json
      )

      :shop_healed
    else
      return :global_heal_skipped if recently_healed_global?

      mark_global_healed!
      InventoryReconcileAllShopsJob.perform_now(fresh_within: 6.hours, push_limit: 100)

      Rails.logger.info(
        {
          event: "system_auto_heal_job.global_done"
        }.to_json
      )

      :global_healed
    end
  end

  private

  def recently_healed_shop?(shop_id)
    ts = Rails.cache.read(shop_cache_key(shop_id))
    ts.present? && ts > SHOP_HEAL_DEBOUNCE.ago
  end

  def mark_shop_healed!(shop_id)
    Rails.cache.write(shop_cache_key(shop_id), Time.current, expires_in: SHOP_HEAL_DEBOUNCE)
  end

  def recently_healed_global?
    ts = Rails.cache.read(global_cache_key)
    ts.present? && ts > GLOBAL_HEAL_DEBOUNCE.ago
  end

  def mark_global_healed!
    Rails.cache.write(global_cache_key, Time.current, expires_in: GLOBAL_HEAL_DEBOUNCE)
  end

  def shop_cache_key(shop_id)
    "system_auto_heal_job:shop:#{shop_id}"
  end

  def global_cache_key
    "system_auto_heal_job:global"
  end
end

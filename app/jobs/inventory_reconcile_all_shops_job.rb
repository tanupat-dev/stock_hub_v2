# frozen_string_literal: true

class InventoryReconcileAllShopsJob < ApplicationJob
  queue_as :reconcile

  SUPPORTED_CHANNELS = %w[tiktok lazada].freeze

  def perform(fresh_within: 6.hours, push_limit: 100)
    started_at = Time.current
    total = 0
    enqueued = 0
    skipped = 0
    errors = 0

    Shop.where(active: true).find_each do |shop|
      total += 1

      skip_reason = reconcile_skip_reason(shop)
      if skip_reason.present?
        skipped += 1
        Rails.logger.info(
          {
            event: "inventory_reconcile_all_shops.skip",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            channel: shop.channel,
            skip_reason: skip_reason
          }.to_json
        )
        next
      end

      begin
        InventoryReconcileJob.perform_later(
          shop.id,
          fresh_within: fresh_within,
          push_limit: push_limit
        )
        enqueued += 1
      rescue => e
        errors += 1
        Rails.logger.error(
          {
            event: "inventory_reconcile_all_shops.enqueue_fail",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            channel: shop.channel,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    payload = {
      event: "inventory_reconcile_all_shops.done",
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

  private

  def reconcile_skip_reason(shop)
    return "inactive" unless shop.active?
    return "unsupported_channel" unless SUPPORTED_CHANNELS.include?(shop.channel)

    case shop.channel
    when "tiktok"
      return "missing_tiktok_credential" if shop.tiktok_credential_id.blank?
      return "missing_shop_cipher" if shop.shop_cipher.blank?
      nil
    when "lazada"
      return "missing_lazada_credential" if shop.lazada_credential_id.blank?
      return "missing_lazada_app" if shop.lazada_app_id.blank? && shop.lazada_credential&.lazada_app.blank?
      nil
    else
      "unsupported_channel"
    end
  end
end

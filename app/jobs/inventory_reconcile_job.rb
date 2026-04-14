# frozen_string_literal: true

class InventoryReconcileJob < ApplicationJob
  queue_as :reconcile

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           Marketplace::Tiktok::Errors::TransientError,
           Marketplace::Lazada::Errors::RateLimitedError,
           Marketplace::Lazada::Errors::TransientError,
           Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: :exponentially_longer,
           attempts: 8

  discard_on ActiveRecord::RecordNotFound

  def perform(shop_id, fresh_within: 6.hours, push_limit: 100)
    shop = Shop.find(shop_id)

    Rails.logger.info(
      {
        event: "inventory_reconcile_job.start",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        fresh_within_seconds: fresh_within.to_i,
        push_limit: push_limit
      }.to_json
    )

    result = Inventory::ReconcileShop.call!(
      shop: shop,
      fresh_within: fresh_within,
      push_limit: push_limit
    )

    payload = {
      event: "inventory_reconcile_job.done",
      shop_id: shop.id,
      shop_code: shop.shop_code,
      channel: shop.channel
    }.merge(result)

    if result[:ok] == false
      Rails.logger.warn(payload.to_json)
    else
      Rails.logger.info(payload.to_json)
    end

    result
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn(
      {
        event: "inventory_reconcile_job.skip",
        shop_id: shop_id,
        skip_reason: "shop_not_found",
        err_message: e.message
      }.to_json
    )
    nil
  rescue => e
    Rails.logger.error(
      {
        event: "inventory_reconcile_job.fail",
        shop_id: shop_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
    raise
  end
end

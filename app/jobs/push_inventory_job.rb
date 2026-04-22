# frozen_string_literal: true

class PushInventoryJob < ApplicationJob
  queue_as :sync_stock

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Tiktok::Errors::TransientError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Lazada::Errors::RateLimitedError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Lazada::Errors::TransientError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(executions) { [ executions * 3, 30 ].min.seconds },
           attempts: 8

  discard_on ActiveRecord::RecordNotFound

  def perform(shop_id, marketplace_item_id, desired_qty, reason:)
    shop = Shop.find(shop_id)
    item = MarketplaceItem.find(marketplace_item_id)

    variant_id = nil
    external_sku = item.external_sku.to_s.strip

    unless item.status.to_s.strip.upcase == "ACTIVATE"
      log_skip(shop, item, desired_qty, reason, "not_activate")
      return :skipped
    end

    product_id = item.external_product_id.to_s.strip
    raise "missing external_product_id for MarketplaceItem id=#{item.id}" if product_id.blank?

    variant_id = item.external_variant_id.to_s.strip
    raise "missing external_variant_id for MarketplaceItem id=#{item.id}" if variant_id.blank?

    mapping = SkuMapping.find_by(
      channel: shop.channel.to_s,
      shop_id: shop.id,
      external_variant_id: variant_id
    )

    if mapping.nil? || mapping.sku.nil?
      log_skip(shop, item, desired_qty, reason, "missing_sku_mapping_for_variant")
      return :skipped
    end

    rollout_skip_reason = StockSync::Rollout.skip_reason(shop: shop, sku: mapping.sku)
    if rollout_skip_reason.present?
      log_skip(
        shop,
        item,
        desired_qty,
        reason,
        rollout_skip_reason,
        sku_id: mapping.sku_id,
        sku: mapping.sku.code,
        shop_stock_sync_enabled: shop.stock_sync_enabled,
        rollout_prefixes: StockSync::Rollout.prefixes
      )
      return :skipped
    end

    case shop.channel
    when "tiktok"
      warehouse_id = item.raw_payload.dig("sku", "inventory", 0, "warehouse_id").to_s.strip
      warehouse_id = "0" if warehouse_id.blank?

      Marketplace::Tiktok::Inventory::Update.call!(
        shop: shop,
        product_id: product_id,
        external_variant_id: variant_id,
        quantity: desired_qty,
        warehouse_id: warehouse_id,
        reason: reason
      )

      mark_success!(shop, variant_id, desired_qty, reason: reason)
      enqueue_targeted_refresh(shop, variant_id)

      Rails.logger.info(
        {
          event: "push_inventory_job.success",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          marketplace_item_id: item.id,
          external_sku: external_sku,
          external_product_id: product_id,
          external_variant_id: variant_id,
          warehouse_id: warehouse_id,
          desired_qty: desired_qty.to_i,
          reason: reason
        }.to_json
      )

      :pushed
    when "lazada"
      Marketplace::Lazada::Stock::Update.call!(
        shop: shop,
        item_id: product_id,
        sku_id: variant_id,
        seller_sku: external_sku,
        quantity: desired_qty,
        reason: reason
      )

      mark_success!(shop, variant_id, desired_qty, reason: reason)
      enqueue_targeted_refresh(shop, variant_id)

      Rails.logger.info(
        {
          event: "push_inventory_job.success",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          marketplace_item_id: item.id,
          external_sku: external_sku,
          external_product_id: product_id,
          external_variant_id: variant_id,
          desired_qty: desired_qty.to_i,
          reason: reason
        }.to_json
      )

      :pushed
    else
      log_skip(shop, item, desired_qty, reason, "unsupported_channel")
      :ignored
    end
  rescue => e
    mark_fail!(
      shop_id,
      item_id: marketplace_item_id,
      variant_id: variant_id,
      desired_qty: desired_qty,
      reason: reason,
      error: e
    )
    raise
  end

  private

  def enqueue_targeted_refresh(shop, variant_id)
    RefreshMarketplaceItemJob.set(wait: 10.seconds).perform_later(shop.id, variant_id)
  rescue => e
    Rails.logger.warn(
      {
        event: "push_inventory_job.refresh_enqueue_fail",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        external_variant_id: variant_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end

  def log_skip(shop, item, desired_qty, reason, skip_reason, extra = {})
    Rails.logger.info(
      {
        event: "push_inventory_job.skip",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        marketplace_item_id: item.id,
        external_sku: item.external_sku,
        status: item.status,
        desired_qty: desired_qty.to_i,
        reason: reason,
        skip_reason: skip_reason
      }.merge(extra).to_json
    )
  end

  def mark_success!(shop, variant_id, desired_qty, reason:)
    mapping = SkuMapping.find_by(
      channel: shop.channel.to_s,
      shop_id: shop.id,
      external_variant_id: variant_id
    )

    if mapping.nil?
      Rails.logger.warn(
        {
          event: "push_inventory_job.state_skip",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          external_variant_id: variant_id,
          desired_qty: desired_qty.to_i,
          reason: reason,
          skip_reason: "missing_sku_mapping_for_variant"
        }.to_json
      )
      return
    end

    sku_id = mapping.sku_id
    if sku_id.blank?
      Rails.logger.warn(
        {
          event: "push_inventory_job.state_skip",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          external_variant_id: variant_id,
          mapping_id: mapping.id,
          desired_qty: desired_qty.to_i,
          reason: reason,
          skip_reason: "mapping_missing_sku_id"
        }.to_json
      )
      return
    end

    state = ShopSkuSyncState.find_or_create_by!(shop_id: shop.id, sku_id: sku_id)
    now = Time.current

    state.update_columns(
      last_pushed_available: desired_qty.to_i,
      last_pushed_at: now,
      fail_count: 0,
      last_failed_at: nil,
      last_error: nil,
      updated_at: now
    )

    if shop.sync_fail_count.to_i > 0 || shop.last_sync_failed_at.present? || shop.last_sync_error.present?
      shop.update_columns(sync_fail_count: 0, last_sync_failed_at: nil, last_sync_error: nil)
    end
  end

  def mark_fail!(shop_id, item_id:, variant_id:, desired_qty:, reason:, error:)
    shop = Shop.find_by(id: shop_id)

    Rails.logger.error(
      {
        event: "push_inventory_job.fail",
        shop_id: shop_id,
        shop_code: shop&.shop_code,
        channel: shop&.channel,
        marketplace_item_id: item_id,
        external_variant_id: variant_id,
        desired_qty: desired_qty.to_i,
        reason: reason,
        err_class: error.class.name,
        err_message: error.message
      }.to_json
    )

    return if shop.nil?

    mapping =
      if variant_id.present?
        SkuMapping.find_by(
          channel: shop.channel.to_s,
          shop_id: shop.id,
          external_variant_id: variant_id
        )
      end

    if mapping&.sku_id.present?
      state = ShopSkuSyncState.find_or_create_by!(shop_id: shop.id, sku_id: mapping.sku_id)
      now = Time.current
      state.update_columns(
        fail_count: state.fail_count.to_i + 1,
        last_failed_at: now,
        last_error: "#{error.class}: #{error.message}",
        updated_at: now
      )
    end

    shop.update_columns(
      sync_fail_count: shop.sync_fail_count.to_i + 1,
      last_sync_failed_at: Time.current,
      last_sync_error: "#{error.class}: #{error.message}"
    )
  rescue
    nil
  end
end

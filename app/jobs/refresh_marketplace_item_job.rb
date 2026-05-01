# frozen_string_literal: true

class RefreshMarketplaceItemJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(e) { [ e * 3, 30 ].min.seconds },
           attempts: 5

  retry_on StandardError,
           wait: ->(e) { [ e * 5, 60 ].min.seconds },
           attempts: 3

  TIKTOK_PAGE_SIZE = 20
  TIKTOK_MAX_PAGES = 2
  ENQUEUE_ONCE_WINDOW = 2.minutes

  class << self
    def enqueue_once!(shop_id, external_variant_id, wait: 30.seconds, reason: nil)
      return :skipped if shop_id.blank? || external_variant_id.blank?
      return :skipped if recently_enqueued?(shop_id, external_variant_id)

      set(wait: wait).perform_later(shop_id, external_variant_id)
      mark_enqueued!(shop_id, external_variant_id)

      Rails.logger.info(
        {
          event: "refresh_marketplace_item_job.enqueue_once",
          result: "enqueued",
          shop_id: shop_id,
          external_variant_id: external_variant_id,
          reason: reason,
          wait_seconds: wait.to_i,
          window_seconds: ENQUEUE_ONCE_WINDOW.to_i
        }.to_json
      )

      :enqueued
    rescue => e
      Rails.logger.warn(
        {
          event: "refresh_marketplace_item_job.enqueue_once_fail",
          shop_id: shop_id,
          external_variant_id: external_variant_id,
          reason: reason,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      :failed
    end

    private

    def recently_enqueued?(shop_id, external_variant_id)
      ts = Rails.cache.read(cache_key(shop_id, external_variant_id))
      ts.present? && ts > ENQUEUE_ONCE_WINDOW.ago
    end

    def mark_enqueued!(shop_id, external_variant_id)
      Rails.cache.write(
        cache_key(shop_id, external_variant_id),
        Time.current,
        expires_in: ENQUEUE_ONCE_WINDOW
      )
    end

    def cache_key(shop_id, external_variant_id)
      "refresh_marketplace_item_job:shop:#{shop_id}:variant:#{external_variant_id}"
    end
  end

  def perform(shop_id, external_variant_id)
    Timeout.timeout(20) do
      shop = Shop.find(shop_id)

      case shop.channel
      when "tiktok"
        refresh_tiktok_variant!(shop, external_variant_id)
      when "lazada"
        refresh_lazada_variant!(shop, external_variant_id)
      else
        Rails.logger.info(
          {
            event: "refresh_marketplace_item_job.skip",
            shop_id: shop_id,
            channel: shop.channel,
            external_variant_id: external_variant_id,
            skip_reason: "unsupported_channel"
          }.to_json
        )
      end
    end

    Rails.logger.info(
      {
        event: "refresh_marketplace_item_job.done",
        shop_id: shop_id,
        external_variant_id: external_variant_id
      }.to_json
    )
  rescue => e
    Rails.logger.error(
      {
        event: "refresh_marketplace_item_job.fail",
        shop_id: shop_id,
        external_variant_id: external_variant_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  end

  private

  def refresh_tiktok_variant!(shop, external_variant_id)
    item = MarketplaceItem.find_by(
      shop_id: shop.id,
      external_variant_id: external_variant_id.to_s
    )

    if item.nil?
      Rails.logger.info(
        {
          event: "refresh_marketplace_item_job.skip",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          external_variant_id: external_variant_id,
          skip_reason: "marketplace_item_not_found"
        }.to_json
      )
      return
    end

    resp = Marketplace::Tiktok::Catalog::List.call!(
      shop: shop,
      page_size: TIKTOK_PAGE_SIZE,
      max_pages: TIKTOK_MAX_PAGES,
      strict: true,
      dry_run: false
    )

    items = Array(resp[:items]).select do |it|
      it[:external_variant_id].to_s == external_variant_id.to_s
    end

    if items.empty?
      Rails.logger.info(
        {
          event: "refresh_marketplace_item_job.variant_not_found_in_limited_scan",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          channel: shop.channel,
          external_variant_id: external_variant_id,
          page_size: TIKTOK_PAGE_SIZE,
          max_pages: TIKTOK_MAX_PAGES
        }.to_json
      )
      return
    end

    Catalog::UpsertMarketplaceItems.call!(
      shop: shop,
      items: items
    )
  ensure
    items = nil
    resp = nil
  end

  def refresh_lazada_variant!(shop, external_variant_id)
    item = MarketplaceItem.find_by!(
      shop_id: shop.id,
      external_variant_id: external_variant_id.to_s
    )

    seller_sku = item.external_sku.to_s.strip
    return if seller_sku.blank?

    resp = Marketplace::Lazada::Catalog::List.call!(
      shop: shop,
      sku_seller_list: [ seller_sku ]
    )

    products = Array(resp[:rows])
    return if products.empty?

    Catalog::UpsertLazadaMarketplaceItems.call!(
      shop: shop,
      products: products
    )
  ensure
    products = nil
    resp = nil
  end
end

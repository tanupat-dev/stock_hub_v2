# frozen_string_literal: true

class PollLazadaCatalogJob < ApplicationJob
  queue_as :default

  retry_on Marketplace::Lazada::Errors::TransientError,
           Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(executions) { [ executions * 3, 30 ].min.seconds },
           attempts: 8

  discard_on ActiveRecord::RecordNotFound

  DEFAULT_LIMIT = 20
  DEFAULT_MAX_PAGES = 200
  PAGE_SLEEP_SECONDS = 3.0
  RATE_LIMIT_SLEEP_SECONDS = 3.0
  MAX_RATE_LIMIT_RETRIES_PER_PAGE = 6

  def perform(shop_id, update_after: nil, filter: "all", limit: DEFAULT_LIMIT, max_pages: DEFAULT_MAX_PAGES, full: false)
    shop = Shop.find(shop_id)

    return unless shop.active?
    return unless shop.channel == "lazada"
    return if shop.lazada_credential_id.nil?

    started_at = Time.current
    limit = normalize_limit(limit)
    max_pages = normalize_max_pages(max_pages)

    offset = 0
    pages = 0
    total_upserted = 0
    total_products = nil
    fetched_products = 0

    effective_update_after =
      if full
        nil
      elsif update_after.present?
        update_after
      elsif shop.catalog_last_polled_at.present?
        shop.catalog_last_polled_at.strftime("%Y-%m-%dT%H:%M:%S%z")
      end

    loop do
      break if pages >= max_pages

      rate_limit_retries = 0
      resp = nil

      loop do
        begin
          resp = Marketplace::Lazada::Catalog::List.call!(
            shop: shop,
            filter: filter,
            limit: limit,
            offset: offset,
            update_after: effective_update_after,
            options: 1
          )
          break
        rescue Marketplace::Lazada::Errors::RateLimitedError => e
          rate_limit_retries += 1

          Rails.logger.warn(
            {
              event: "poll.lazada.catalog.rate_limited",
              shop_id: shop.id,
              shop_code: shop.shop_code,
              offset: offset,
              page: pages + 1,
              retries_for_page: rate_limit_retries,
              sleep_seconds: RATE_LIMIT_SLEEP_SECONDS,
              err_message: e.message
            }.to_json
          )

          raise if rate_limit_retries >= MAX_RATE_LIMIT_RETRIES_PER_PAGE
          sleep RATE_LIMIT_SLEEP_SECONDS
        end
      end

      rows = Array(resp[:rows])
      total_products = resp[:total].to_i if total_products.nil?
      break if rows.empty?

      pages += 1
      fetched_products += rows.size

      upsert_result = Catalog::UpsertLazadaMarketplaceItems.call!(
        shop: shop,
        products: rows
      )

      total_upserted += upsert_result[:upserted].to_i
      offset += rows.size

      Rails.logger.info(
        {
          event: "poll.lazada.catalog.progress",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          page: pages,
          offset: offset,
          fetched_products: fetched_products,
          total_products: total_products,
          page_size: rows.size,
          upserted_total: total_upserted,
          full: full,
          update_after: effective_update_after
        }.to_json
      )

      break if offset >= total_products
      break if rows.size < limit

      sleep PAGE_SLEEP_SECONDS
    end

    truncated = total_products.present? && fetched_products < total_products.to_i
    now = Time.current

    shop.update_columns(
      catalog_last_polled_at: now,
      catalog_last_total_count: total_products,
      catalog_last_error: nil,
      catalog_fail_count: 0,
      updated_at: now
    )

    Rails.logger.info(
      {
        event: "poll.lazada.catalog.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        filter: filter,
        update_after: effective_update_after,
        full: full,
        pages: pages,
        limit: limit,
        fetched_products: fetched_products,
        upserted: total_upserted,
        total_products: total_products,
        truncated: truncated,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: true,
      shop_id: shop.id,
      pages: pages,
      limit: limit,
      fetched_products: fetched_products,
      upserted: total_upserted,
      total_products: total_products,
      truncated: truncated,
      full: full
    }
  rescue => e
    now = Time.current

    Shop.where(id: shop_id).update_all(
      [
        "catalog_fail_count = COALESCE(catalog_fail_count, 0) + 1, catalog_last_error = ?, updated_at = ?",
        "#{e.class}: #{e.message}",
        now
      ]
    )

    Rails.logger.error(
      {
        event: "poll.lazada.catalog.fail",
        shop_id: shop_id,
        offset: offset,
        pages: pages,
        limit: limit,
        upserted_before_fail: total_upserted,
        fetched_products_before_fail: fetched_products,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  end

  private

  def normalize_limit(limit)
    n = limit.to_i
    n = DEFAULT_LIMIT if n <= 0
    n = 20 if n > 20
    n
  end

  def normalize_max_pages(max_pages)
    n = max_pages.to_i
    n = DEFAULT_MAX_PAGES if n <= 0
    n
  end
end

# frozen_string_literal: true

class PollCatalogJob < ApplicationJob
  queue_as :default

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           Marketplace::Tiktok::Errors::TransientError,
           wait: :exponentially_longer,
           attempts: 10

  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(executions) { [ executions * 3, 30 ].min.seconds },
           attempts: 8

  discard_on ActiveRecord::RecordNotFound

  PER_RUN_MAX_PAGES = 5
  DEFAULT_PAGE_SIZE = 50

  def perform(
    shop_id,
    enqueue_sync_stock: true,
    enqueue_sync_sku_master: true,
    dry_run: false,
    resume: true,
    max_pages: 200,
    page_size: DEFAULT_PAGE_SIZE,
    filter_deleted: true
  )
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.blank?
    return if shop.shop_cipher.blank?

    page_size = normalize_page_size(page_size)
    remaining_pages = normalize_max_pages(max_pages)
    pages_this_run = [ remaining_pages, PER_RUN_MAX_PAGES ].min

    started_token = resume ? shop.catalog_last_page_token : nil

    resp = Marketplace::Tiktok::Catalog::List.call!(
      shop: shop,
      page_size: page_size,
      max_pages: pages_this_run,
      product_status: "ALL",
      start_page_token: started_token,
      strict: true,
      dry_run: dry_run
    )

    items = Array(resp[:items])

    deleted_count =
      if filter_deleted
        items.count { |it| it[:status].to_s.upcase == "DELETED" }
      else
        0
      end

    upserted =
      if dry_run
        0
      else
        Catalog::UpsertMarketplaceItems.call!(shop: shop, items: items)
      end

    pages_fetched = resp[:pages].to_i
    next_token = resp[:last_page_token].presence
    next_remaining_pages = [ remaining_pages - pages_fetched, 0 ].max
    should_continue = next_token.present? && next_remaining_pages.positive?
    fully_drained = next_token.blank?

    unless dry_run
      shop.update_columns(
        catalog_last_page_token: next_token,
        catalog_last_polled_at: Time.current,
        catalog_last_total_count: resp[:total_count],
        catalog_fail_count: 0,
        catalog_last_error: nil,
        updated_at: Time.current
      )
    end

    Rails.logger.info(
      {
        event: "poll.catalog.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        dry_run: dry_run,
        resume: resume,
        started_token: started_token,
        last_page_token: next_token,
        pages: pages_fetched,
        pages_this_run: pages_this_run,
        remaining_pages_before: remaining_pages,
        remaining_pages_after: next_remaining_pages,
        total_count: resp[:total_count],
        fetched_products: resp[:fetched_products],
        fetched_variants: resp[:fetched_variants],
        received_items: items.size,
        deleted_count: deleted_count,
        upserted: upserted,
        fully_drained: fully_drained,
        should_continue: should_continue,
        next_step: next_step_name(
          dry_run: dry_run,
          should_continue: should_continue,
          fully_drained: fully_drained,
          enqueue_sync_sku_master: enqueue_sync_sku_master
        ),
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    if !dry_run && should_continue
      self.class.set(wait: 5.seconds).perform_later(
        shop.id,
        enqueue_sync_stock: enqueue_sync_stock,
        enqueue_sync_sku_master: enqueue_sync_sku_master,
        dry_run: dry_run,
        resume: true,
        max_pages: next_remaining_pages,
        page_size: page_size,
        filter_deleted: filter_deleted
      )
    elsif !dry_run && fully_drained && enqueue_sync_sku_master
      SyncSkuMasterJob.perform_later(
        shop.id,
        enqueue_sync_stock: enqueue_sync_stock,
        dry_run: dry_run
      )
    end

    {
      ok: true,
      shop_id: shop.id,
      channel: shop.channel,
      dry_run: dry_run,
      pages: pages_fetched,
      pages_this_run: pages_this_run,
      remaining_pages_after: next_remaining_pages,
      total_count: resp[:total_count],
      received_items: items.size,
      deleted_count: deleted_count,
      upserted: upserted,
      last_page_token: next_token,
      fully_drained: fully_drained,
      should_continue: should_continue
    }
  rescue => e
    begin
      shop&.update_columns(
        catalog_fail_count: shop.catalog_fail_count.to_i + 1,
        catalog_last_error: "#{e.class}: #{e.message}".slice(0, 1000),
        catalog_last_polled_at: Time.current,
        updated_at: Time.current
      )
    rescue
      nil
    end

    Rails.logger.error(
      {
        event: "poll.catalog.fail",
        shop_id: shop_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  ensure
    items = nil
    resp = nil
  end

  private

  def normalize_page_size(page_size)
    n = page_size.to_i
    n = DEFAULT_PAGE_SIZE if n <= 0
    n = DEFAULT_PAGE_SIZE if n > DEFAULT_PAGE_SIZE
    n
  end

  def normalize_max_pages(max_pages)
    n = max_pages.to_i
    n.positive? ? n : PER_RUN_MAX_PAGES
  end

  def next_step_name(dry_run:, should_continue:, fully_drained:, enqueue_sync_sku_master:)
    return "dry_run" if dry_run
    return "enqueue_next_catalog_chunk" if should_continue
    return "enqueue_sync_sku_master" if fully_drained && enqueue_sync_sku_master

    "done"
  end
end

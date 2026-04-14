# frozen_string_literal: true

class PollCatalogJob < ApplicationJob
  queue_as :default

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           Marketplace::Tiktok::Errors::TransientError,
           wait: :exponentially_longer,
           attempts: 10

  discard_on ActiveRecord::RecordNotFound

  def perform(
    shop_id,
    enqueue_sync_stock: true,
    enqueue_sync_sku_master: true,
    dry_run: false,
    resume: true,
    max_pages: 200,
    page_size: 50,
    filter_deleted: true
  )
    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.blank?
    return if shop.shop_cipher.blank?

    started_token = (resume ? shop.catalog_last_page_token : nil)

    resp = Marketplace::Tiktok::Catalog::List.call!(
      shop: shop,
      page_size: page_size,
      max_pages: max_pages,
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

    Rails.logger.info(
      {
        event: "poll.catalog.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        channel: shop.channel,
        dry_run: dry_run,
        resume: resume,
        started_token: started_token,
        last_page_token: resp[:last_page_token],
        pages: resp[:pages],
        total_count: resp[:total_count],
        fetched_products: resp[:fetched_products],
        fetched_variants: resp[:fetched_variants],
        received_items: items.size,
        deleted_count: deleted_count,
        upserted: upserted,
        next_step: (!dry_run && enqueue_sync_sku_master) ? "enqueue_sync_sku_master" : "skip_sync_sku_master"
      }.to_json
    )

    unless dry_run
      shop.update_columns(
        catalog_last_page_token: resp[:last_page_token],
        catalog_last_polled_at: Time.current,
        catalog_last_total_count: resp[:total_count],
        catalog_fail_count: 0,
        catalog_last_error: nil,
        updated_at: Time.current
      )
    end

    if !dry_run && enqueue_sync_sku_master
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
      pages: resp[:pages],
      total_count: resp[:total_count],
      received_items: items.size,
      deleted_count: deleted_count,
      upserted: upserted,
      last_page_token: resp[:last_page_token]
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
  end
end

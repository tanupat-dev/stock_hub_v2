# frozen_string_literal: true

class PollTiktokOrdersJob < ApplicationJob
  queue_as :poll_orders

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

  SAFETY_LAG_SECONDS = 120
  FIRST_RUN_LOOKBACK_SECONDS = 3600

  # RAM 512MB safe:
  # real volume < 1,000 orders/day, so many small jobs are safer than one huge job.
  MAX_WINDOW_SECONDS = 15.minutes.to_i
  MAX_PAGES = 10
  PAGE_SIZE = 50

  UPSERT_BATCH_SIZE = 20
  DETAIL_ENRICH_LIMIT_PER_RUN = 5

  def perform(shop_id, since: nil, until_time: nil)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.nil?
    return if shop.shop_cipher.blank?

    now = Time.current
    now_ts = now.to_i

    requested_window_lt = ((until_time || now).to_i - SAFETY_LAG_SECONDS)

    cursor_ts =
      if since.present?
        since.to_i
      elsif shop.last_seen_update_time.present?
        shop.last_seen_update_time.to_i
      else
        now_ts - FIRST_RUN_LOOKBACK_SECONDS
      end

    window_ge = [ cursor_ts - SAFETY_LAG_SECONDS, 0 ].max
    window_lt = [ requested_window_lt, window_ge + MAX_WINDOW_SECONDS ].min
    window_lt = [ window_lt, window_ge ].max

    if window_lt <= window_ge
      shop.update_columns(last_polled_at: now, updated_at: Time.current)

      return {
        ok: true,
        fetched: 0,
        pages: 0,
        cursor_written: cursor_ts,
        fully_drained: true,
        reason: "empty_window"
      }
    end

    pages = 0
    fetched = 0
    max_update_time_seen = window_ge
    page_token = nil
    fully_drained = true
    detail_enriched = 0

    loop do
      if pages >= MAX_PAGES
        fully_drained = false
        break
      end

      pages += 1

      resp = Marketplace::Tiktok::Orders::Search.call!(
        shop: shop,
        update_time_ge: window_ge,
        update_time_lt: window_lt,
        page_size: PAGE_SIZE,
        page_token: page_token
      )

      rows = Array(resp[:rows])
      fetched += rows.size

      if rows.any?
        rows.each_slice(UPSERT_BATCH_SIZE) do |batch|
          Orders::UpsertFromSearchRows.call!(shop: shop, rows: batch)
        end

        remaining_detail_limit = DETAIL_ENRICH_LIMIT_PER_RUN - detail_enriched
        if remaining_detail_limit.positive?
          detail_enriched += enrich_missing_tiktok_details!(
            shop: shop,
            rows: rows,
            limit: remaining_detail_limit
          )
        end

        rows.each do |r|
          ut = r["update_time"].to_i
          max_update_time_seen = ut if ut > max_update_time_seen
        end
      end

      page_token = resp[:next_page_token].presence
      break if page_token.blank?

      sleep(rand * 0.2 + 0.1)
    ensure
      rows = nil
      resp = nil
    end

    cursor_written =
      if fetched == 0
        window_lt
      elsif fully_drained
        [ max_update_time_seen, window_lt ].min
      else
        cursor_ts
      end

    shop.update_columns(
      last_seen_update_time: cursor_written,
      last_polled_at: now,
      updated_at: Time.current
    )

    enqueue_next_window_if_needed(shop, requested_window_lt, cursor_written)

    Rails.logger.info(
      {
        event: "poll.tiktok.orders.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        update_time_ge: window_ge,
        update_time_lt: window_lt,
        requested_window_lt: requested_window_lt,
        cursor_written: cursor_written,
        fetched: fetched,
        pages: pages,
        fully_drained: fully_drained,
        detail_enriched: detail_enriched,
        max_window_seconds: MAX_WINDOW_SECONDS,
        page_size: PAGE_SIZE,
        max_pages: MAX_PAGES,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: true,
      shop_id: shop.id,
      fetched: fetched,
      pages: pages,
      cursor_written: cursor_written,
      fully_drained: fully_drained,
      detail_enriched: detail_enriched
    }
  end

  private

  def enqueue_next_window_if_needed(shop, requested_window_lt, cursor_written)
    return if cursor_written >= requested_window_lt

    self.class.set(wait: 10.seconds).perform_later(shop.id)

    Rails.logger.info(
      {
        event: "poll.tiktok.orders.next_window_enqueued",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        cursor_written: cursor_written,
        requested_window_lt: requested_window_lt
      }.to_json
    )
  rescue => e
    Rails.logger.warn(
      {
        event: "poll.tiktok.orders.next_window_enqueue_failed",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end

  def enrich_missing_tiktok_details!(shop:, rows:, limit:)
    return 0 if limit.to_i <= 0

    count = 0

    eligible_orders_for_detail(shop: shop, rows: rows).first(limit).each do |order|
      begin
        detail = Marketplace::Tiktok::Orders::Get.call!(
          shop: shop,
          order_id: order.external_order_id
        )

        Orders::Tiktok::UpdateFromDetail.call!(
          order: order,
          payload: detail
        )

        count += 1
      rescue => e
        Rails.logger.warn(
          {
            event: "tiktok.order.detail.enrich_failed",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            order_id: order.external_order_id,
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end
    end

    count
  end

  def eligible_orders_for_detail(shop:, rows:)
    external_ids = Array(rows).map { |r| r["id"].to_s }.reject(&:blank?).uniq
    return [] if external_ids.empty?

    Order.where(channel: "tiktok", shop_id: shop.id, external_order_id: external_ids)
         .where("buyer_name IS NULL OR province IS NULL")
         .order(updated_at_external: :desc, id: :desc)
         .limit(DETAIL_ENRICH_LIMIT_PER_RUN)
         .to_a
  end
end

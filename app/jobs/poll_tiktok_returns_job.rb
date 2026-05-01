# frozen_string_literal: true

class PollTiktokReturnsJob < ApplicationJob
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

  MAX_WINDOW_SECONDS = 15.minutes.to_i
  MAX_PAGES = 10
  PAGE_SIZE = 50
  UPSERT_BATCH_SIZE = 20

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
      elsif shop.tiktok_returns_last_seen_update_time.present?
        shop.tiktok_returns_last_seen_update_time.to_i
      else
        now_ts - FIRST_RUN_LOOKBACK_SECONDS
      end

    window_ge = [ cursor_ts - SAFETY_LAG_SECONDS, 0 ].max
    window_lt = [ requested_window_lt, window_ge + MAX_WINDOW_SECONDS ].min
    window_lt = [ window_lt, window_ge ].max

    if window_lt <= window_ge
      shop.update_columns(
        tiktok_returns_last_polled_at: now,
        updated_at: Time.current
      )

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

    loop do
      if pages >= MAX_PAGES
        fully_drained = false
        break
      end

      pages += 1

      resp = Marketplace::Tiktok::Returns::Search.call!(
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
          Marketplace::Tiktok::UpsertReturnShipments.call!(
            shop: shop,
            rows: batch
          )
        end

        rows.each do |row|
          ut = row["update_time"].to_i
          max_update_time_seen = ut if ut > max_update_time_seen
        end
      end

      page_token = resp[:next_page_token].presence
      break if page_token.blank?

      sleep(rand * 0.3 + 0.2)
    ensure
      rows = nil
      resp = nil
    end

    cursor_written =
      if fetched == 0
        window_lt
      elsif fully_drained
        window_lt
      else
        cursor_ts
      end

    shop.update_columns(
      tiktok_returns_last_seen_update_time: cursor_written,
      tiktok_returns_last_polled_at: now,
      updated_at: Time.current
    )

    enqueue_next_window_if_needed(shop, requested_window_lt, cursor_written)

    Rails.logger.info(
      {
        event: "poll.tiktok.returns.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        update_time_ge: window_ge,
        update_time_lt: window_lt,
        requested_window_lt: requested_window_lt,
        cursor_written: cursor_written,
        max_update_time_seen: max_update_time_seen,
        fetched: fetched,
        pages: pages,
        fully_drained: fully_drained,
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
      fully_drained: fully_drained
    }
  end

  private

  def enqueue_next_window_if_needed(shop, requested_window_lt, cursor_written)
    return if cursor_written >= requested_window_lt

    self.class.set(wait: 10.seconds).perform_later(shop.id)

    Rails.logger.info(
      {
        event: "poll.tiktok.returns.next_window_enqueued",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        cursor_written: cursor_written,
        requested_window_lt: requested_window_lt
      }.to_json
    )
  rescue => e
    Rails.logger.warn(
      {
        event: "poll.tiktok.returns.next_window_enqueue_failed",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end
end

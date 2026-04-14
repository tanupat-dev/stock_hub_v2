# frozen_string_literal: true

class PollTiktokReturnsJob < ApplicationJob
  queue_as :poll_orders

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           Marketplace::Tiktok::Errors::TransientError,
           wait: :exponentially_longer,
           attempts: 10

  discard_on ActiveRecord::RecordNotFound

  SAFETY_LAG_SECONDS = 120
  FIRST_RUN_LOOKBACK_SECONDS = 3600
  MAX_PAGES = 500
  PAGE_SIZE = 100

  def perform(shop_id, since: nil, until_time: nil)
    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.nil?
    return if shop.shop_cipher.blank?

    now = Time.current
    now_ts = now.to_i

    window_lt = ((until_time || now).to_i - SAFETY_LAG_SECONDS)

    cursor_ts =
      if since.present?
        since.to_i
      elsif shop.tiktok_returns_last_seen_update_time.present?
        shop.tiktok_returns_last_seen_update_time.to_i
      else
        now_ts - FIRST_RUN_LOOKBACK_SECONDS
      end

    window_ge = [ cursor_ts - SAFETY_LAG_SECONDS, 0 ].max
    window_lt = [ window_lt, window_ge ].max

    if window_lt <= window_ge
      shop.update_columns(
        tiktok_returns_last_polled_at: now,
        updated_at: Time.current
      )
      return { ok: true, fetched: 0, pages: 0, cursor_written: cursor_ts }
    end

    pages = 0
    fetched = 0
    max_update_time_seen = window_ge
    page_token = nil

    loop do
      pages += 1
      raise "poll exceeded max pages (#{MAX_PAGES})" if pages > MAX_PAGES

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
        Marketplace::Tiktok::UpsertReturnShipments.call!(
          shop: shop,
          rows: rows
        )

        rows.each do |row|
          ut = row["update_time"].to_i
          max_update_time_seen = ut if ut > max_update_time_seen
        end
      end

      page_token = resp[:next_page_token].presence
      break if page_token.blank?

      # 🔥 NEW: throttle กันโดน 429 (สำคัญสุด)
      sleep(rand * 0.3 + 0.2)
    end

    cursor_written = (fetched == 0 ? window_lt : max_update_time_seen)

    shop.update_columns(
      tiktok_returns_last_seen_update_time: cursor_written,
      tiktok_returns_last_polled_at: now,
      updated_at: Time.current
    )

    Rails.logger.info(
      {
        event: "poll.tiktok.returns.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        update_time_ge: window_ge,
        update_time_lt: window_lt,
        cursor_written: cursor_written,
        fetched: fetched,
        pages: pages
      }.to_json
    )

    { ok: true, shop_id: shop.id, fetched: fetched, pages: pages, cursor_written: cursor_written }
  end
end

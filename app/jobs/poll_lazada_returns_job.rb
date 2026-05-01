# frozen_string_literal: true

class PollLazadaReturnsJob < ApplicationJob
  queue_as :poll_orders

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

  FIRST_RUN_LOOKBACK_SECONDS = 3600
  SAFETY_LAG_SECONDS = 120

  MAX_WINDOW_SECONDS = 15.minutes.to_i
  MAX_PAGES = 10
  PAGE_SIZE = 50

  def perform(shop_id, since: nil, until_time: nil)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "lazada"
    return if shop.lazada_credential_id.nil?

    now = Time.current
    requested_window_end_ms = ((until_time || now).to_time.to_f * 1000).to_i - (SAFETY_LAG_SECONDS * 1000)

    cursor_ms =
      if since.present?
        since.to_i * 1000
      elsif shop.lazada_returns_last_seen_update_time.present?
        shop.lazada_returns_last_seen_update_time.to_i * 1000
      else
        ((now - FIRST_RUN_LOOKBACK_SECONDS).to_f * 1000).to_i
      end

    window_start_ms = [ cursor_ms - (SAFETY_LAG_SECONDS * 1000), 0 ].max
    max_window_end_ms = window_start_ms + (MAX_WINDOW_SECONDS * 1000)
    window_end_ms = [ requested_window_end_ms, max_window_end_ms ].min
    window_end_ms = [ window_end_ms, window_start_ms ].max

    if window_end_ms <= window_start_ms
      shop.update_columns(
        lazada_returns_last_polled_at: now,
        updated_at: Time.current
      )

      return {
        ok: true,
        fetched: 0,
        pages: 0,
        cursor_written: cursor_ms / 1000,
        fully_drained: true,
        reason: "empty_window"
      }
    end

    page_no = 1
    pages = 0
    fetched = 0
    max_modified_seen_ms = window_start_ms
    fully_drained = true

    loop do
      if pages >= MAX_PAGES
        fully_drained = false
        break
      end

      pages += 1

      resp = Marketplace::Lazada::Returns::Search.call!(
        shop: shop,
        modified_from_ms: window_start_ms,
        modified_to_ms: window_end_ms,
        page_no: page_no,
        page_size: PAGE_SIZE
      )

      items = Array(resp[:items])
      break if items.blank?

      items.each do |summary|
        reverse_order_id = summary["reverse_order_id"].to_s
        next if reverse_order_id.blank?

        detail = Marketplace::Lazada::Returns::Detail.call!(
          shop: shop,
          reverse_order_id: reverse_order_id
        )

        raw_return = Returns::Lazada::Transformer.call(
          summary: summary,
          detail: detail
        )

        Returns::Lazada::Upsert.call!(
          shop: shop,
          raw_return: raw_return
        )

        Array(summary["reverse_order_lines"]).each do |line|
          raw = line["return_order_line_gmt_modified"].to_i
          next if raw <= 0

          modified_ms = raw >= 1_000_000_000_000 ? raw : raw * 1000
          max_modified_seen_ms = modified_ms if modified_ms > max_modified_seen_ms
        end

        fetched += 1
      ensure
        detail = nil
        raw_return = nil
      end

      Rails.logger.info(
        {
          event: "poll.lazada.returns.progress",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          page: page_no,
          pages: pages,
          fetched: fetched,
          modified_from_ms: window_start_ms,
          modified_to_ms: window_end_ms,
          max_modified_seen_ms: max_modified_seen_ms,
          fully_drained: fully_drained
        }.to_json
      )

      break if items.size < PAGE_SIZE

      page_no += 1
      sleep(rand * 0.3 + 0.2)
    ensure
      items = nil
      resp = nil
    end

    cursor_written =
      if fetched == 0
        window_end_ms / 1000
      elsif fully_drained
        window_end_ms / 1000
      else
        cursor_ms / 1000
      end

    shop.update_columns(
      lazada_returns_last_seen_update_time: cursor_written,
      lazada_returns_last_polled_at: now,
      updated_at: Time.current
    )

    enqueue_next_window_if_needed(shop, requested_window_end_ms / 1000, cursor_written)

    Rails.logger.info(
      {
        event: "poll.lazada.returns.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        fetched: fetched,
        pages: pages,
        cursor_written: cursor_written,
        max_modified_seen_ms: max_modified_seen_ms,
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

  def enqueue_next_window_if_needed(shop, requested_window_end_ts, cursor_written)
    return if cursor_written >= requested_window_end_ts

    self.class.set(wait: 10.seconds).perform_later(shop.id)

    Rails.logger.info(
      {
        event: "poll.lazada.returns.next_window_enqueued",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        cursor_written: cursor_written,
        requested_window_end_ts: requested_window_end_ts
      }.to_json
    )
  rescue => e
    Rails.logger.warn(
      {
        event: "poll.lazada.returns.next_window_enqueue_failed",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end
end

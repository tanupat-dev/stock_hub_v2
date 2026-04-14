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
  PAGE_SIZE = 100
  SAFETY_LAG_SECONDS = 120

  def perform(shop_id, since: nil, until_time: nil)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "lazada"
    return if shop.lazada_credential_id.nil?

    now = Time.current
    window_end_ms = ((until_time || now).to_time.to_f * 1000).to_i - (SAFETY_LAG_SECONDS * 1000)

    cursor_ms =
      if since.present?
        since.to_i * 1000
      elsif shop.lazada_returns_last_seen_update_time.present?
        shop.lazada_returns_last_seen_update_time.to_i * 1000
      else
        ((now - FIRST_RUN_LOOKBACK_SECONDS).to_f * 1000).to_i
      end

    window_start_ms = [ cursor_ms - (SAFETY_LAG_SECONDS * 1000), 0 ].max
    window_end_ms = [ window_end_ms, window_start_ms ].max

    if window_end_ms <= window_start_ms
      shop.update_columns(
        lazada_returns_last_polled_at: now,
        updated_at: Time.current
      )
      return { ok: true, fetched: 0, pages: 0, cursor_written: cursor_ms / 1000 }
    end

    page_no = 1
    pages = 0
    fetched = 0
    max_modified_seen_ms = window_start_ms

    loop do
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
      end

      Rails.logger.info(
        {
          event: "poll.lazada.returns.progress",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          page: page_no,
          fetched: fetched,
          modified_from_ms: window_start_ms,
          modified_to_ms: window_end_ms,
          max_modified_seen_ms: max_modified_seen_ms
        }.to_json
      )

      break if items.size < PAGE_SIZE
      page_no += 1
    end

    cursor_written = (fetched == 0 ? window_end_ms : max_modified_seen_ms) / 1000

    shop.update_columns(
      lazada_returns_last_seen_update_time: cursor_written,
      lazada_returns_last_polled_at: now,
      updated_at: Time.current
    )

    Rails.logger.info(
      {
        event: "poll.lazada.returns.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        fetched: fetched,
        pages: page_no,
        cursor_written: cursor_written,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: true,
      shop_id: shop.id,
      fetched: fetched,
      pages: page_no,
      cursor_written: cursor_written
    }
  end
end

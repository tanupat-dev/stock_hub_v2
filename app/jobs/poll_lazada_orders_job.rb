# frozen_string_literal: true

class PollLazadaOrdersJob < ApplicationJob
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

  FIRST_RUN_LOOKBACK_SECONDS = 7_200
  SAFETY_LAG_SECONDS = 120
  LIMIT = 100
  MAX_PAGES = 20

  def perform(shop_id, since: nil, until_time: nil)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "lazada"
    return if shop.lazada_credential_id.nil?

    now = Time.current
    window_lt = ((until_time || now).to_time.utc - SAFETY_LAG_SECONDS.seconds)

    cursor =
      if since.present?
        Time.at(since.to_i).utc
      elsif shop.last_seen_update_time.present? && shop.last_seen_update_time.to_i > 0
        Time.at(shop.last_seen_update_time.to_i).utc
      else
        FIRST_RUN_LOOKBACK_SECONDS.seconds.ago.utc
      end

    window_ge = [ cursor - SAFETY_LAG_SECONDS.seconds, Time.at(0).utc ].max

    if window_lt <= window_ge
      shop.update_columns(
        last_polled_at: now,
        updated_at: Time.current
      )

      return {
        ok: true,
        shop_id: shop.id,
        fetched: 0,
        pages: 0,
        cursor_written: shop.last_seen_update_time.to_i,
        fully_drained: true
      }
    end

    offset = 0
    fetched = 0
    pages = 0
    max_update_time_seen = shop.last_seen_update_time.to_i
    fully_drained = true

    loop do
      if pages >= MAX_PAGES
        fully_drained = false
        break
      end

      resp = Marketplace::Lazada::Orders::Search.call!(
        shop: shop,
        update_after: window_ge.iso8601,
        update_before: window_lt.iso8601,
        offset: offset,
        limit: LIMIT
      )

      orders = Array(resp[:rows])
      break if orders.blank?

      pages += 1

      ids = orders.map { |o| o["order_id"] }.compact

      items = Marketplace::Lazada::Orders::Items.call!(
        shop: shop,
        order_ids: ids
      )

      rows = Orders::Lazada::Transformer.call(
        orders: orders,
        items: items
      )

      rows.each do |raw_order|
        Orders::Lazada::Upsert.call!(
          shop: shop,
          raw_order: raw_order
        )
      end

      rows.each do |r|
        ut = r["update_time"].to_i
        max_update_time_seen = ut if ut > max_update_time_seen
      end

      fetched += orders.size
      offset += orders.size

      Rails.logger.info(
        {
          event: "poll.lazada.orders.progress",
          shop_id: shop.id,
          shop_code: shop.shop_code,
          page: pages,
          fetched: fetched,
          offset: offset,
          window_ge: window_ge.iso8601,
          window_lt: window_lt.iso8601,
          max_update_time_seen: max_update_time_seen,
          fully_drained: fully_drained
        }.to_json
      )

      break if orders.size < LIMIT

      sleep(rand * 0.3 + 0.2)
    end

    cursor_written =
      if fetched == 0
        window_lt.to_i
      elsif fully_drained
        max_update_time_seen
      else
        shop.last_seen_update_time.to_i
      end

    shop.update_columns(
      last_seen_update_time: cursor_written,
      last_polled_at: now,
      updated_at: Time.current
    )

    Rails.logger.info(
      {
        event: "poll.lazada.orders.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        fetched: fetched,
        pages: pages,
        window_ge: window_ge.iso8601,
        window_lt: window_lt.iso8601,
        cursor_written: cursor_written,
        fully_drained: fully_drained,
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
end

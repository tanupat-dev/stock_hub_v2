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

  FIRST_RUN_LOOKBACK_SECONDS = 3600
  LIMIT = 100

  def perform(shop_id, since: nil)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "lazada"
    return if shop.lazada_credential_id.nil?

    cursor =
      if since.present?
        Time.at(since.to_i).utc
      elsif shop.last_seen_update_time.present?
        Time.at(shop.last_seen_update_time.to_i).utc
      else
        FIRST_RUN_LOOKBACK_SECONDS.seconds.ago.utc
      end

    offset = 0
    fetched = 0
    pages = 0
    max_update_time_seen = shop.last_seen_update_time.to_i

    loop do
      resp = Marketplace::Lazada::Orders::Search.call!(
        shop: shop,
        update_after: cursor.iso8601,
        offset: offset,
        limit: LIMIT
      )

      orders = Array(resp[:rows])
      break if orders.blank?

      pages += 1

      ids = orders.map { |o| o["order_id"] }

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
          cursor: cursor.iso8601,
          max_update_time_seen: max_update_time_seen
        }.to_json
      )

      break if orders.size < LIMIT
    end

    shop.update_columns(
      last_seen_update_time: max_update_time_seen,
      last_polled_at: Time.current,
      updated_at: Time.current
    )

    Rails.logger.info(
      {
        event: "poll.lazada.orders.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        fetched: fetched,
        pages: pages,
        cursor_written: max_update_time_seen,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: true,
      shop_id: shop.id,
      fetched: fetched,
      pages: pages,
      cursor_written: max_update_time_seen
    }
  end
end

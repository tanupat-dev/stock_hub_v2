# frozen_string_literal: true

class PollTiktokOrdersJob < ApplicationJob
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
  DETAIL_ENRICH_LIMIT_PER_RUN = 20

  def perform(shop_id, since: nil, until_time: nil)
    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.nil? # placeholder กันพลาด
    return if shop.shop_cipher.blank?

    now = Time.current
    now_ts = now.to_i

    # window_lt ใช้ now - lag กัน refresh delay
    window_lt = ((until_time || now).to_i - SAFETY_LAG_SECONDS)

    # cursor_ts จาก param > shop.last_seen_update_time > first run lookback
    cursor_ts =
      if since.present?
        since.to_i
      elsif shop.last_seen_update_time.present?
        shop.last_seen_update_time.to_i
      else
        now_ts - FIRST_RUN_LOOKBACK_SECONDS
      end

    window_ge = [ cursor_ts - SAFETY_LAG_SECONDS, 0 ].max
    window_lt = [ window_lt, window_ge ].max

    # ✅ window ว่างก็ไม่ต้องยิง API
    if window_lt <= window_ge
      shop.update_columns(last_polled_at: now, updated_at: Time.current)
      return { ok: true, fetched: 0, pages: 0, cursor_written: cursor_ts }
    end

    pages = 0
    fetched = 0
    max_update_time_seen = window_ge
    page_token = nil

    loop do
      pages += 1
      raise "poll exceeded max pages (#{MAX_PAGES})" if pages > MAX_PAGES

      resp = Marketplace::Tiktok::Orders::Search.call!(
        shop: shop,
        update_time_ge: window_ge,
        update_time_lt: window_lt,
        page_size: PAGE_SIZE,
        page_token: page_token
      )

      rows = Array(resp[:rows])
      fetched += rows.size

      # ✅ สำคัญ: rows ว่าง "ห้าม" upsert
      if rows.any?
        Orders::UpsertFromSearchRows.call!(shop: shop, rows: rows)
        enrich_missing_tiktok_details!(shop: shop, rows: rows)

        rows.each do |r|
          ut = r["update_time"].to_i
          max_update_time_seen = ut if ut > max_update_time_seen
        end
      end

      page_token = resp[:next_page_token].presence
      break if page_token.blank?
    end

    # ✅ cursor advance:
    # - ถ้าไม่มี rows เลย ให้ขยับไป window_lt (แปลว่าเรา cover ช่วงนี้แล้ว)
    # - ถ้ามี rows ให้ขยับไป max_update_time_seen
    cursor_written = (fetched == 0 ? window_lt : max_update_time_seen)

    shop.update_columns(
      last_seen_update_time: cursor_written,
      last_polled_at: now,
      updated_at: Time.current
    )

    Rails.logger.info(
      {
        event: "poll.tiktok.orders.done",
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

  private

  def enrich_missing_tiktok_details!(shop:, rows:)
    eligible_orders_for_detail(shop: shop, rows: rows).first(DETAIL_ENRICH_LIMIT_PER_RUN).each do |order|
      begin
        detail = Marketplace::Tiktok::Orders::Get.call!(
          shop: shop,
          order_id: order.external_order_id
        )

        Orders::Tiktok::UpdateFromDetail.call!(
          order: order,
          detail: detail
        )
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
  end

  def eligible_orders_for_detail(shop:, rows:)
    external_ids = Array(rows).map { |r| r["id"].to_s }.reject(&:blank?).uniq
    return [] if external_ids.empty?

    Order.where(channel: "tiktok", shop_id: shop.id, external_order_id: external_ids)
         .where("buyer_name IS NULL OR province IS NULL")
         .order(updated_at_external: :desc, id: :desc)
         .to_a
  end
end

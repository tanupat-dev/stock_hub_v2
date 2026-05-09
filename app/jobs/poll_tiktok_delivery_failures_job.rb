# frozen_string_literal: true

class PollTiktokDeliveryFailuresJob < ApplicationJob
  queue_as :poll_orders

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           Marketplace::Tiktok::Errors::TransientError,
           wait: :exponentially_longer,
           attempts: 8

  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(executions) { [ executions * 3, 30 ].min.seconds },
           attempts: 6

  discard_on ActiveRecord::RecordNotFound

  DEFAULT_LIMIT = 30
  DEFAULT_MAX_AGE_DAYS = 30

  def perform(shop_id, limit: DEFAULT_LIMIT, max_age_days: DEFAULT_MAX_AGE_DAYS)
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.nil?
    return if shop.shop_cipher.blank?

    stats = {
      scanned: 0,
      created: 0,
      skipped: 0,
      failed: 0
    }

    candidate_orders(shop: shop, limit: limit, max_age_days: max_age_days).each do |order|
      stats[:scanned] += 1

      begin
        tracking_data = Marketplace::Tiktok::Fulfillment::GetTracking.call!(
          shop: shop,
          order_id: order.external_order_id
        )

        shipment = Returns::Tiktok::CreateFromDeliveryFailed.call!(
          order: order,
          tracking_data: tracking_data
        )

        if shipment.present?
          stats[:created] += 1
        else
          stats[:skipped] += 1
        end
      rescue => e
        stats[:failed] += 1

        Rails.logger.warn(
          {
            event: "poll.tiktok.delivery_failures.order_failed",
            shop_id: shop.id,
            shop_code: shop.shop_code,
            order_id: order.id,
            external_order_id: order.external_order_id,
            tracking_number: order.raw_payload&.dig("tracking_number"),
            err_class: e.class.name,
            err_message: e.message
          }.to_json
        )
      end

      sleep(rand * 0.15 + 0.05)
    end

    Rails.logger.info(
      {
        event: "poll.tiktok.delivery_failures.done",
        shop_id: shop.id,
        shop_code: shop.shop_code,
        limit: limit,
        max_age_days: max_age_days,
        stats: stats,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: stats[:failed].zero?,
      shop_id: shop.id,
      stats: stats
    }
  end

  private

  def candidate_orders(shop:, limit:, max_age_days:)
    cutoff = Time.current - max_age_days.to_i.days

    Order
      .where(channel: "tiktok", shop_id: shop.id, status: "IN_TRANSIT")
      .where("orders.updated_at >= ?", cutoff)
      .where("NULLIF(orders.raw_payload->>'tracking_number', '') IS NOT NULL")
      .where(
        <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM order_lines ol
            INNER JOIN inventory_actions ia
              ON ia.order_line_id = ol.id
             AND ia.action_type = 'commit'
            WHERE ol.order_id = orders.id
          )
        SQL
      )
      .where(
        <<~SQL.squish
          NOT EXISTS (
            SELECT 1
            FROM return_shipments rs
            WHERE rs.order_id = orders.id
          )
        SQL
      )
      .order(updated_at_external: :desc, id: :desc)
      .limit(normalize_limit(limit))
      .includes(:shop, order_lines: :sku)
      .to_a
  end

  def normalize_limit(value)
    raw = value.to_i
    return DEFAULT_LIMIT if raw <= 0
    return 100 if raw > 100

    raw
  end
end

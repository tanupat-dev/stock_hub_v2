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
  DEFAULT_ORDER_DIRECTION = "desc"
  DEFAULT_RECHECK_AFTER_HOURS = 6

  CHECK_META_KEY = "_delivery_failure_check"

  VALID_ORDER_DIRECTIONS = %w[
    asc
    desc
  ].freeze

  def perform(
    shop_id,
    limit: DEFAULT_LIMIT,
    max_age_days: DEFAULT_MAX_AGE_DAYS,
    order_direction: DEFAULT_ORDER_DIRECTION,
    recheck_after_hours: DEFAULT_RECHECK_AFTER_HOURS
  )
    started_at = Time.current

    shop = Shop.find(shop_id)
    return unless shop.active?
    return unless shop.channel == "tiktok"
    return if shop.tiktok_credential_id.nil?
    return if shop.shop_cipher.blank?

    normalized_order_direction = normalize_order_direction(order_direction)
    normalized_recheck_after_hours = normalize_recheck_after_hours(recheck_after_hours)

    stats = {
      scanned: 0,
      created: 0,
      skipped: 0,
      failed: 0
    }

    candidate_orders(
      shop: shop,
      limit: limit,
      max_age_days: max_age_days,
      order_direction: normalized_order_direction,
      recheck_after_hours: normalized_recheck_after_hours
    ).each do |order|
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
          mark_checked!(order, tracking_data, result: "no_rts_tracking_event")
        end
      rescue => e
        stats[:failed] += 1
        mark_checked!(order, nil, result: "check_failed", error: e)

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
        order_direction: normalized_order_direction,
        recheck_after_hours: normalized_recheck_after_hours,
        stats: stats,
        duration_ms: ((Time.current - started_at) * 1000).round
      }.to_json
    )

    {
      ok: stats[:failed].zero?,
      shop_id: shop.id,
      stats: stats,
      order_direction: normalized_order_direction,
      recheck_after_hours: normalized_recheck_after_hours
    }
  end

  private

  def candidate_orders(shop:, limit:, max_age_days:, order_direction:, recheck_after_hours:)
    cutoff = Time.current - max_age_days.to_i.days
    recheck_cutoff = Time.current - recheck_after_hours.hours
    direction = order_direction.to_sym

    Order
      .where(channel: "tiktok", shop_id: shop.id, status: "IN_TRANSIT")
      .where("orders.updated_at >= ?", cutoff)
      .where("NULLIF(orders.raw_payload->>'tracking_number', '') IS NOT NULL")
      .where(
        <<~SQL.squish,
          (
            orders.raw_payload->:check_meta_key IS NULL
            OR NULLIF(orders.raw_payload->:check_meta_key->>'checked_at', '') IS NULL
            OR (orders.raw_payload->:check_meta_key->>'checked_at')::timestamp < :recheck_cutoff
          )
        SQL
        check_meta_key: CHECK_META_KEY,
        recheck_cutoff: recheck_cutoff
      )
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
      .order(updated_at_external: direction, id: direction)
      .limit(normalize_limit(limit))
      .includes(:shop, order_lines: :sku)
      .to_a
  end

  def mark_checked!(order, tracking_data, result:, error: nil)
    payload = order.raw_payload || {}
    latest_event = latest_tracking_event(tracking_data)

    updated_payload = payload.deep_dup
    updated_payload[CHECK_META_KEY] = {
      "checked_at" => Time.current.iso8601,
      "result" => result,
      "latest_action_code" => latest_event&.dig("action_code"),
      "latest_description" => latest_event&.dig("description"),
      "latest_update_time_millis" => latest_event&.dig("update_time_millis"),
      "error_class" => error&.class&.name,
      "error_message" => error&.message
    }.compact

    order.update_columns(
      raw_payload: updated_payload,
      updated_at: Time.current
    )
  rescue => e
    Rails.logger.warn(
      {
        event: "poll.tiktok.delivery_failures.mark_checked_failed",
        order_id: order&.id,
        external_order_id: order&.external_order_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end

  def latest_tracking_event(tracking_data)
    Array(tracking_data&.dig("tracking"))
      .max_by { |event| event["update_time_millis"].to_i }
  end

  def normalize_limit(value)
    raw = value.to_i
    return DEFAULT_LIMIT if raw <= 0
    return 100 if raw > 100

    raw
  end

  def normalize_order_direction(value)
    raw = value.to_s.strip.downcase
    return raw if VALID_ORDER_DIRECTIONS.include?(raw)

    DEFAULT_ORDER_DIRECTION
  end

  def normalize_recheck_after_hours(value)
    raw = value.to_i
    return DEFAULT_RECHECK_AFTER_HOURS if raw <= 0
    return 24 if raw > 24

    raw
  end
end

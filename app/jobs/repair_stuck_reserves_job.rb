# frozen_string_literal: true

class RepairStuckReservesJob < ApplicationJob
  queue_as :default

  SUPPORTED_CHANNELS = %w[tiktok lazada].freeze

  def perform(older_than_hours: 1)
    started_at = Time.current
    repaired = 0
    skipped = 0
    errors = 0

    stuck_orders(cutoff: older_than_hours.hours.ago).find_each do |order|
      if commit_safe?(order)
        repair!(order)
        repaired += 1
      else
        log_insufficient_stock(order)
        skipped += 1
      end
    rescue => e
      errors += 1
      log_order_error(order, e)
    end

    log_summary(repaired:, skipped:, errors:, started_at:)

    { ok: errors == 0, repaired:, skipped:, errors: }
  end

  private

  # Finds IN_TRANSIT marketplace orders with a reserve action older than +cutoff+
  # that has no corresponding commit or release on the same order line.
  def stuck_orders(cutoff:)
    stuck_line_ids = InventoryAction
      .where(action_type: "reserve")
      .where("created_at < ?", cutoff)
      .where.not(order_line_id: nil)
      .where(
        "NOT EXISTS (" \
          "SELECT 1 FROM inventory_actions closing " \
          "WHERE closing.order_line_id = inventory_actions.order_line_id " \
          "AND closing.action_type IN ('commit', 'release')" \
        ")"
      )
      .select(:order_line_id)

    stuck_order_ids = OrderLine.where(id: stuck_line_ids).select(:order_id)

    Order
      .where(id: stuck_order_ids)
      .where(status: "IN_TRANSIT", channel: SUPPORTED_CHANNELS)
  end

  # Read-only safety check: all open-reserve lines have on_hand >= needed quantity.
  # Intentionally no DB lock here — Inventory::Commit takes the lock during the actual repair.
  def commit_safe?(order)
    open_lines = Orders::OpenReserve.open_lines(order)
    return true if open_lines.empty?

    open_lines.all? do |line|
      qty = Orders::OpenReserve.open_quantity(line)
      next true if qty <= 0

      sku = line.sku
      next false if sku.nil?

      balance = sku.inventory_balance
      next false if balance.nil?

      balance.on_hand.to_i >= qty
    end
  end

  def repair!(order)
    Orders::RepairMissingInventoryActions.call!(
      order: order,
      raw_order: { "update_time" => order.updated_time_external.to_i },
      previous_status: nil,
      source: "repair_stuck_reserves_job"
    )
  end

  def log_insufficient_stock(order)
    open_lines = Orders::OpenReserve.open_lines(order)

    line_details = open_lines.filter_map do |line|
      qty = Orders::OpenReserve.open_quantity(line)
      next if qty <= 0

      sku = line.sku
      balance = sku&.inventory_balance
      oldest_reserve_at = InventoryAction
        .where(order_line_id: line.id, action_type: "reserve")
        .minimum(:created_at)

      {
        order_line_id: line.id,
        sku_id: sku&.id,
        sku: sku&.code,
        on_hand: balance&.on_hand,
        needed_qty: qty,
        oldest_reserve_at: oldest_reserve_at,
        reserve_age_hours: oldest_reserve_at ? ((Time.current - oldest_reserve_at) / 3600.0).round(1) : nil
      }
    end

    Rails.logger.warn(
      {
        event: "repair_stuck_reserves.skipped_insufficient_stock",
        order_id: order.id,
        external_order_id: order.external_order_id,
        channel: order.channel,
        shop_id: order.shop_id,
        lines: line_details
      }.to_json
    )
  end

  def log_order_error(order, error)
    Rails.logger.error(
      {
        event: "repair_stuck_reserves.order_error",
        order_id: order.id,
        external_order_id: order.external_order_id,
        channel: order.channel,
        shop_id: order.shop_id,
        err_class: error.class.name,
        err_message: error.message
      }.to_json
    )
  end

  def log_summary(repaired:, skipped:, errors:, started_at:)
    payload = {
      event: "repair_stuck_reserves.done",
      repaired:,
      skipped:,
      errors:,
      duration_ms: ((Time.current - started_at) * 1000).round
    }

    if errors.positive?
      Rails.logger.error(payload.to_json)
    else
      Rails.logger.info(payload.to_json)
    end
  end
end

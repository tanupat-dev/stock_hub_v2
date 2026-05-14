# frozen_string_literal: true

require "test_helper"
require "stringio"

class RepairStuckReservesJobTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0, stock_identity: @identity)
    @balance  = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 5, reserved: 0)
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  def make_order(channel: "tiktok", status: "IN_TRANSIT")
    shop =
      if channel == "tiktok"
        @shop
      else
        Shop.create!(channel: channel, shop_code: "#{channel}-#{SecureRandom.hex(4)}", name: channel, active: true)
      end
    Order.create!(
      channel: channel,
      shop: shop,
      external_order_id: "#{channel.upcase}-#{SecureRandom.hex(4)}",
      status: status
    )
  end

  def make_line(order, sku: @sku, quantity: 1)
    OrderLine.create!(
      order: order,
      sku: sku,
      quantity: quantity,
      idempotency_key: "line-#{SecureRandom.hex(4)}"
    )
  end

  def seed_reserve(line, qty: nil, age: 2.hours)
    qty ||= line.quantity
    action = InventoryAction.create!(
      sku: line.sku,
      order_line_id: line.id,
      action_type: "reserve",
      quantity: qty,
      idempotency_key: "reserve-#{line.id}-#{SecureRandom.hex(4)}",
      meta: {}
    )
    action.update_columns(created_at: age.ago)
    line.sku.inventory_balance.increment!(:reserved, qty)
    action
  end

  def seed_commit(line, qty: nil)
    qty ||= line.quantity
    InventoryAction.create!(
      sku: line.sku,
      order_line_id: line.id,
      action_type: "commit",
      quantity: qty,
      idempotency_key: "commit-#{line.id}-#{SecureRandom.hex(4)}",
      meta: {}
    )
  end

  def capture_logs
    old_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old_logger
  end

  def run_job(**kwargs)
    RepairStuckReservesJob.perform_now(**kwargs)
  end

  # -------------------------------------------------------
  # Happy path: sufficient stock → repair
  # -------------------------------------------------------

  test "repairs IN_TRANSIT tiktok order with old open reserve when on_hand is sufficient" do
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 2.hours)

    result = run_job

    assert_equal true,  result[:ok]
    assert_equal 1,     result[:repaired]
    assert_equal 0,     result[:skipped]
    assert_equal 0,     result[:errors]

    assert InventoryAction.exists?(order_line_id: line.id, action_type: "commit")
    assert_equal 4, @balance.reload.on_hand
    assert_equal 0, @balance.reserved
  end

  test "repairs IN_TRANSIT lazada order the same way" do
    lazada_identity = StockIdentity.create!
    lazada_sku      = Sku.create!(code: "LAZ1", barcode: "LB1", buffer_quantity: 0, stock_identity: lazada_identity)
    lazada_balance  = InventoryBalance.create!(stock_identity: lazada_identity, sku: lazada_sku, on_hand: 3, reserved: 0)

    order = make_order(channel: "lazada")
    line  = make_line(order, sku: lazada_sku)
    seed_reserve(line, qty: 1, age: 90.minutes)

    result = run_job

    assert_equal 1, result[:repaired]
    assert InventoryAction.exists?(order_line_id: line.id, action_type: "commit")
    assert_equal 2, lazada_balance.reload.on_hand
    assert_equal 0, lazada_balance.reserved
  end

  test "repair is idempotent: running the job twice does not double-commit" do
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 2.hours)

    run_job
    result2 = run_job

    assert_equal 0, result2[:repaired]
    assert_equal 1, InventoryAction.where(order_line_id: line.id, action_type: "commit").count
  end

  # -------------------------------------------------------
  # Skip: insufficient on_hand → warn but do not commit
  # -------------------------------------------------------

  test "skips and logs warning when on_hand is less than needed qty" do
    @balance.update!(on_hand: 0)
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 2.hours)

    logs = capture_logs do
      result = run_job

      assert_equal 0, result[:repaired]
      assert_equal 1, result[:skipped]
      assert_equal 0, result[:errors]
    end

    refute InventoryAction.exists?(order_line_id: line.id, action_type: "commit")
    assert_includes logs, "repair_stuck_reserves.skipped_insufficient_stock"
    assert_includes logs, @sku.code
    assert_includes logs, '"on_hand":0'
    assert_includes logs, '"needed_qty":1'
  end

  test "skip log includes reserve age in hours" do
    @balance.update!(on_hand: 0)
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 3.hours)

    logs = capture_logs { run_job }

    assert_includes logs, "reserve_age_hours"
  end

  # -------------------------------------------------------
  # Mixed batch: some safe, some unsafe
  # -------------------------------------------------------

  test "repairs safe orders and skips unsafe orders in the same batch" do
    # Safe order: on_hand=5 (from @balance)
    order_safe = make_order
    line_safe  = make_line(order_safe)
    seed_reserve(line_safe, qty: 1, age: 2.hours)

    # Unsafe order: on_hand=0
    identity2 = StockIdentity.create!
    sku2      = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0, stock_identity: identity2)
    InventoryBalance.create!(stock_identity: identity2, sku: sku2, on_hand: 0, reserved: 0)
    order_unsafe = make_order
    line_unsafe  = make_line(order_unsafe, sku: sku2)
    seed_reserve(line_unsafe, qty: 1, age: 2.hours)

    result = run_job

    assert_equal 1, result[:repaired]
    assert_equal 1, result[:skipped]
    assert_equal 0, result[:errors]

    assert InventoryAction.exists?(order_line_id: line_safe.id, action_type: "commit")
    refute InventoryAction.exists?(order_line_id: line_unsafe.id, action_type: "commit")
  end

  # -------------------------------------------------------
  # Age filter: only reserves older than the threshold
  # -------------------------------------------------------

  test "ignores orders whose reserve is younger than 1 hour" do
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 30.minutes)

    result = run_job

    assert_equal 0, result[:repaired]
    assert_equal 0, result[:skipped]
    refute InventoryAction.exists?(order_line_id: line.id, action_type: "commit")
  end

  test "older_than_hours parameter controls the age cutoff" do
    order_old   = make_order
    line_old    = make_line(order_old)
    seed_reserve(line_old, qty: 1, age: 3.hours)

    identity2 = StockIdentity.create!
    sku2      = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0, stock_identity: identity2)
    InventoryBalance.create!(stock_identity: identity2, sku: sku2, on_hand: 5, reserved: 0)
    order_young = make_order
    line_young  = make_line(order_young, sku: sku2)
    seed_reserve(line_young, qty: 1, age: 90.minutes)

    # With a 2-hour cutoff, only the 3-hour-old reserve qualifies
    result = run_job(older_than_hours: 2)

    assert_equal 1, result[:repaired]
    assert InventoryAction.exists?(order_line_id: line_old.id, action_type: "commit")
    refute InventoryAction.exists?(order_line_id: line_young.id, action_type: "commit")
  end

  # -------------------------------------------------------
  # Already-closed reserves are excluded
  # -------------------------------------------------------

  test "does not pick up orders where reserve is already committed" do
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 2.hours)
    seed_commit(line, qty: 1)

    result = run_job

    assert_equal 0, result[:repaired]
    assert_equal 0, result[:skipped]
  end

  # -------------------------------------------------------
  # Status filter: only IN_TRANSIT
  # -------------------------------------------------------

  test "ignores orders that are not IN_TRANSIT" do
    %w[AWAITING_FULFILLMENT READY_TO_SHIP DELIVERED CANCELLED].each_with_index do |status, i|
      identity = StockIdentity.create!
      sku      = Sku.create!(code: "ST#{i}", barcode: "BT#{i}", buffer_quantity: 0, stock_identity: identity)
      InventoryBalance.create!(stock_identity: identity, sku: sku, on_hand: 5, reserved: 0)
      order = make_order(status: status)
      line  = make_line(order, sku: sku)
      seed_reserve(line, qty: 1, age: 2.hours)
    end

    result = run_job

    assert_equal 0, result[:repaired]
    assert_equal 0, result[:skipped]
  end

  # -------------------------------------------------------
  # Channel filter: tiktok and lazada only
  # -------------------------------------------------------

  test "ignores shopee and pos orders" do
    %w[shopee pos].each_with_index do |channel, i|
      identity = StockIdentity.create!
      sku      = Sku.create!(code: "CH#{i}", barcode: "CB#{i}", buffer_quantity: 0, stock_identity: identity)
      InventoryBalance.create!(stock_identity: identity, sku: sku, on_hand: 5, reserved: 0)
      shop  = Shop.create!(channel: channel, shop_code: "#{channel}-#{SecureRandom.hex(4)}", name: channel, active: true)
      order = Order.create!(channel: channel, shop: shop, external_order_id: "#{channel.upcase}-#{SecureRandom.hex(4)}", status: "IN_TRANSIT")
      line  = make_line(order, sku: sku)
      seed_reserve(line, qty: 1, age: 2.hours)
    end

    result = run_job

    assert_equal 0, result[:repaired]
    assert_equal 0, result[:skipped]
  end

  # -------------------------------------------------------
  # Summary log
  # -------------------------------------------------------

  test "logs a done event with repaired/skipped/errors counts" do
    order = make_order
    line  = make_line(order)
    seed_reserve(line, qty: 1, age: 2.hours)

    logs = capture_logs { run_job }

    assert_includes logs, "repair_stuck_reserves.done"
    assert_includes logs, '"repaired":1'
    assert_includes logs, '"skipped":0'
    assert_includes logs, '"errors":0'
  end
end

# test/services/inventory/oversell_allocator_test.rb
require "test_helper"

class Inventory::OversellAllocatorTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0, stock_identity: @identity)
    InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 0)

    @order = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "TT-001", status: "IN_TRANSIT")
  end

  def call_allocator(shortfall:)
    Inventory::OversellAllocator.call!(sku: @sku, shortfall_qty: shortfall)
  end

  def make_line(quantity:, key:)
    OrderLine.create!(order: @order, sku: @sku, quantity: quantity, idempotency_key: key)
  end

  def reserve(line, qty:, key:, reserved_at: nil)
    action = InventoryAction.create!(
      sku: @sku, order_line_id: line.id,
      action_type: "reserve", quantity: qty,
      idempotency_key: key, meta: {}
    )
    action.update_columns(created_at: reserved_at) if reserved_at
    action
  end

  def release(line, qty:, key:)
    InventoryAction.create!(
      sku: @sku, order_line_id: line.id,
      action_type: "release", quantity: qty,
      idempotency_key: key, meta: {}
    )
  end

  def commit(line, qty:, key:)
    InventoryAction.create!(
      sku: @sku, order_line_id: line.id,
      action_type: "commit", quantity: qty,
      idempotency_key: key, meta: {}
    )
  end

  # -------------------------------------------------------
  # Zero / empty cases
  # -------------------------------------------------------
  test "returns empty array when shortfall_qty is zero" do
    line = make_line(quantity: 3, key: "l1")
    reserve(line, qty: 3, key: "r1")

    assert_equal [], call_allocator(shortfall: 0)
  end

  test "returns empty array when shortfall_qty is negative" do
    line = make_line(quantity: 3, key: "l1")
    reserve(line, qty: 3, key: "r1")

    assert_equal [], call_allocator(shortfall: -1)
  end

  test "returns empty array when no InventoryAction records exist for sku" do
    assert_equal [], call_allocator(shortfall: 5)
  end

  # -------------------------------------------------------
  # Single line
  # -------------------------------------------------------
  test "single line: allocates exactly the shortfall when shortfall < outstanding" do
    line = make_line(quantity: 5, key: "l1")
    reserve(line, qty: 5, key: "r1")

    result = call_allocator(shortfall: 3)

    assert_equal 1, result.size
    assert_equal line.id, result[0][:order_line_id]
    assert_equal 3, result[0][:qty]
  end

  test "single line: allocates full outstanding when shortfall >= outstanding" do
    line = make_line(quantity: 3, key: "l1")
    reserve(line, qty: 3, key: "r1")

    result = call_allocator(shortfall: 5)

    assert_equal 1, result.size
    assert_equal 3, result[0][:qty]
  end

  # -------------------------------------------------------
  # Open reserve accounts for releases and commits
  # -------------------------------------------------------
  test "outstanding is reserve minus release minus commit" do
    line = make_line(quantity: 5, key: "l1")
    reserve(line, qty: 5, key: "r1")
    release(line, qty: 2, key: "rel1")  # outstanding = 5 - 2 = 3

    result = call_allocator(shortfall: 5)

    assert_equal 1, result.size
    assert_equal 3, result[0][:qty]  # only 3 outstanding, not 5
  end

  test "line with outstanding == 0 (fully released) is excluded" do
    line1 = make_line(quantity: 3, key: "l1")
    line2 = make_line(quantity: 2, key: "l2")

    reserve(line1, qty: 3, key: "r1")
    release(line1, qty: 3, key: "rel1")  # line1 outstanding = 0 → excluded
    reserve(line2, qty: 2, key: "r2")

    result = call_allocator(shortfall: 5)

    assert_equal 1, result.size
    assert_equal line2.id, result[0][:order_line_id]
    assert_equal 2, result[0][:qty]
  end

  test "line with outstanding == 0 (fully committed) is excluded" do
    line1 = make_line(quantity: 3, key: "l1")
    line2 = make_line(quantity: 2, key: "l2")

    reserve(line1, qty: 3, key: "r1")
    commit(line1, qty: 3, key: "c1")   # line1 outstanding = 0 → excluded
    reserve(line2, qty: 2, key: "r2")

    result = call_allocator(shortfall: 5)

    assert_equal 1, result.size
    assert_equal line2.id, result[0][:order_line_id]
  end

  # -------------------------------------------------------
  # FIFO across multiple lines
  # -------------------------------------------------------
  test "allocates FIFO: oldest reserve action first" do
    line1 = make_line(quantity: 3, key: "l1")
    line2 = make_line(quantity: 2, key: "l2")
    line3 = make_line(quantity: 2, key: "l3")

    reserve(line1, qty: 3, key: "r1", reserved_at: 2.hours.ago)
    reserve(line2, qty: 2, key: "r2", reserved_at: 1.hour.ago)
    reserve(line3, qty: 2, key: "r3")  # most recent

    # shortfall = 4: takes all of line1 (3) then 1 from line2
    result = call_allocator(shortfall: 4)

    assert_equal 2, result.size
    assert_equal line1.id, result[0][:order_line_id]
    assert_equal 3,        result[0][:qty]
    assert_equal line2.id, result[1][:order_line_id]
    assert_equal 1,        result[1][:qty]
    # line3 is not touched
  end

  test "FIFO: shortfall exactly fills first line, second line untouched" do
    line1 = make_line(quantity: 3, key: "l1")
    line2 = make_line(quantity: 2, key: "l2")

    reserve(line1, qty: 3, key: "r1", reserved_at: 1.hour.ago)
    reserve(line2, qty: 2, key: "r2")

    result = call_allocator(shortfall: 3)

    assert_equal 1, result.size
    assert_equal line1.id, result[0][:order_line_id]
    assert_equal 3, result[0][:qty]
  end

  test "FIFO: shortfall larger than all outstanding allocates across all lines" do
    line1 = make_line(quantity: 2, key: "l1")
    line2 = make_line(quantity: 2, key: "l2")

    reserve(line1, qty: 2, key: "r1", reserved_at: 1.hour.ago)
    reserve(line2, qty: 2, key: "r2")

    result = call_allocator(shortfall: 10)

    assert_equal 2, result.size
    assert_equal 2, result[0][:qty]
    assert_equal 2, result[1][:qty]
  end
end

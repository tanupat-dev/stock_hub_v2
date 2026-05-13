# test/services/orders/repair_missing_inventory_actions_test.rb
require "test_helper"

class Orders::RepairMissingInventoryActionsTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3, stock_identity: @identity)
    @balance  = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 0)
    @order    = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "TT-001", status: "READY_TO_SHIP")
    @line     = OrderLine.create!(order: @order, sku: @sku, quantity: 2, idempotency_key: "line-1")
  end

  def repair(previous_status: nil)
    Orders::RepairMissingInventoryActions.call!(
      order: @order,
      previous_status: previous_status,
      source: "test"
    )
  end

  # Helper: manually seed an open reserve (bypasses Reserve service to keep setup simple)
  def seed_open_reserve(line, qty: line.quantity)
    InventoryAction.create!(
      sku: line.sku,
      order_line_id: line.id,
      action_type: "reserve",
      quantity: qty,
      idempotency_key: "seed-reserve-#{line.id}",
      meta: {}
    )
    line.sku.inventory_balance.increment!(:reserved, qty)
  end

  # -------------------------------------------------------
  # Reservable status — unactioned lines
  # -------------------------------------------------------
  test "reserves unactioned lines when order is in a reservable status" do
    result = repair

    assert_equal :reserve, result[:action]
    assert_equal "reserved_missing_lines", result[:reason]
    assert_includes result[:candidate_line_ids], @line.id

    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "reserve")
    assert_equal 2, @balance.reload.reserved
  end

  test "repair is idempotent for reservable: already_applied on second call" do
    repair
    result2 = repair

    # Line now has a reserve action, so it is no longer a candidate
    assert_equal "no_missing_reserve_lines", result2[:reason]
    assert_equal [], result2[:candidate_line_ids]
    assert_equal 1, InventoryAction.where(order_line_id: @line.id, action_type: "reserve").count
  end

  # -------------------------------------------------------
  # Reservable status — all lines already actioned
  # -------------------------------------------------------
  test "skips repair when all lines already have inventory actions" do
    seed_open_reserve(@line)

    result = repair

    assert_nil result[:action]
    assert_equal "no_missing_reserve_lines", result[:reason]
    assert_equal [], result[:candidate_line_ids]
    assert_equal 1, InventoryAction.where(order_line_id: @line.id, action_type: "reserve").count
  end

  # -------------------------------------------------------
  # Reservable status — line without SKU is silently ignored
  # -------------------------------------------------------
  test "lines without sku are excluded from repair candidates" do
    OrderLine.create!(order: @order, sku_id: nil, quantity: 1, idempotency_key: "no-sku")

    result = repair

    # Only @line (with sku) is a candidate; nil-sku line never appears
    assert_includes result[:candidate_line_ids], @line.id
    refute result[:candidate_line_ids].any? { |id| id.nil? }
  end

  # -------------------------------------------------------
  # IN_TRANSIT — open reserve exists → commit it
  # -------------------------------------------------------
  test "commits open reserve when order is IN_TRANSIT and prior reserve exists" do
    seed_open_reserve(@line)
    @order.update!(status: "IN_TRANSIT")

    result = repair(previous_status: "READY_TO_SHIP")

    assert_equal :commit, result[:action]
    assert_includes result[:commit_candidate_line_ids], @line.id
    assert_equal [], result[:missing_prior_reserve_line_ids]

    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "commit")
    b = @balance.reload
    assert_equal 8, b.on_hand
    assert_equal 0, b.reserved
  end

  test "IN_TRANSIT commit is idempotent: second repair is a no-op" do
    seed_open_reserve(@line)
    @order.update!(status: "IN_TRANSIT")

    repair(previous_status: "READY_TO_SHIP")
    result2 = repair(previous_status: "READY_TO_SHIP")

    # After first repair, open reserve = 0 and committed = qty → no longer a commit candidate
    assert_equal [], result2[:commit_candidate_line_ids]
    assert_equal 1, InventoryAction.where(order_line_id: @line.id, action_type: "commit").count
  end

  # -------------------------------------------------------
  # IN_TRANSIT — no prior reserve → warn but do not commit
  # -------------------------------------------------------
  test "does not commit when IN_TRANSIT and line has no prior reserve" do
    @order.update!(status: "IN_TRANSIT")

    result = repair(previous_status: nil)

    assert_equal :commit, result[:action]  # action key is :commit even when only a warning
    assert_equal [], result[:commit_candidate_line_ids]
    assert_includes result[:missing_prior_reserve_line_ids], @line.id
    assert_nil result[:apply_result]

    refute InventoryAction.exists?(order_line_id: @line.id, action_type: "commit")
    assert_equal 10, @balance.reload.on_hand  # unchanged
  end

  # -------------------------------------------------------
  # IN_TRANSIT — mixed: one line reserved, one not
  # -------------------------------------------------------
  test "IN_TRANSIT commits reserved lines and warns about unreserved lines" do
    identity2 = StockIdentity.create!
    sku2      = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0, stock_identity: identity2)
    InventoryBalance.create!(stock_identity: identity2, sku: sku2, on_hand: 5, reserved: 0)
    line2 = OrderLine.create!(order: @order, sku: sku2, quantity: 1, idempotency_key: "line-2")

    seed_open_reserve(@line)  # @line has open reserve; line2 does not
    @order.update!(status: "IN_TRANSIT")

    result = repair(previous_status: "READY_TO_SHIP")

    assert_includes result[:commit_candidate_line_ids], @line.id
    assert_includes result[:missing_prior_reserve_line_ids], line2.id

    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "commit")
    refute InventoryAction.exists?(order_line_id: line2.id, action_type: "commit")
  end

  # -------------------------------------------------------
  # Non-repairable statuses
  # -------------------------------------------------------
  test "does nothing for DELIVERED (terminal) status" do
    @order.update!(status: "DELIVERED")

    result = repair

    assert_nil result[:action]
    assert_equal "status_not_repairable", result[:reason]
    assert_equal "DELIVERED", result[:status]
    refute InventoryAction.exists?(order_line_id: @line.id)
  end

  test "does nothing for COMPLETED (terminal) status" do
    @order.update!(status: "COMPLETED")

    result = repair

    assert_nil result[:action]
    assert_equal "status_not_repairable", result[:reason]
  end

  test "does nothing for CANCELLED status" do
    @order.update!(status: "CANCELLED")

    result = repair

    assert_nil result[:action]
    assert_equal "status_not_repairable", result[:reason]
    refute InventoryAction.exists?(order_line_id: @line.id)
  end

  test "does nothing for UNPAID (noop) status" do
    @order.update!(status: "UNPAID")

    result = repair

    assert_nil result[:action]
    assert_equal "status_not_repairable", result[:reason]
  end

  # -------------------------------------------------------
  # Return structure
  # -------------------------------------------------------
  test "return hash always includes ok, order_id, channel, and repair_run_id" do
    result = repair

    assert result[:ok]
    assert_equal @order.id, result[:order_id]
    assert_equal "tiktok", result[:channel]
    assert_not_nil result[:repair_run_id]
    assert_equal "test", result[:source]
  end
end

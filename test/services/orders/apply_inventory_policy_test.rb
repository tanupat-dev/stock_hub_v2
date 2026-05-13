# test/services/orders/apply_inventory_policy_test.rb
require "test_helper"

class Orders::ApplyInventoryPolicyTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3, stock_identity: @identity)
    @balance  = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 0)
    @order    = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "TT-001", status: "READY_TO_SHIP")
    @line     = OrderLine.create!(order: @order, sku: @sku, quantity: 2, idempotency_key: "line-1")
    @prefix   = "tiktok:order:TT-001"
  end

  def call_policy(action: nil, line_actions: nil, prefix: @prefix)
    Orders::ApplyInventoryPolicy.call!(
      order: @order,
      action: action,
      line_actions: line_actions,
      idempotency_prefix: prefix,
      meta: {}
    )
  end

  # -------------------------------------------------------
  # Reserve
  # -------------------------------------------------------
  test "reserve increases reserved and creates InventoryAction with order_line_id" do
    result = call_policy(action: :reserve)

    assert result[:ok]
    line_result = result[:results][0]
    assert_equal :reserved, line_result[:result]
    assert_equal @line.id, line_result[:order_line_id]

    assert_equal 2, @balance.reload.reserved
    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "reserve", quantity: 2)
  end

  test "reserve is idempotent: second call with same prefix returns already_applied" do
    call_policy(action: :reserve)
    result2 = call_policy(action: :reserve)

    assert_equal :already_applied, result2[:results][0][:result]
    assert_equal 2, @balance.reload.reserved
    assert_equal 1, InventoryAction.where(order_line_id: @line.id, action_type: "reserve").count
  end

  test "reserve returns not_enough_stock and freezes balance when online_available is insufficient" do
    # online_available = on_hand(4) - reserved(0) - buffer(3) = 1 < line qty(2)
    @balance.update!(on_hand: 4)

    result = call_policy(action: :reserve)

    assert_equal :not_enough_stock, result[:results][0][:result]
    b = @balance.reload
    assert b.frozen_now?
    assert_equal "not_enough_stock", b.freeze_reason
    refute InventoryAction.exists?(order_line_id: @line.id, action_type: "reserve")
  end

  test "reserve returns frozen when balance is already frozen" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "manual")

    result = call_policy(action: :reserve)

    assert_equal :frozen, result[:results][0][:result]
    refute InventoryAction.exists?(order_line_id: @line.id, action_type: "reserve")
  end

  # -------------------------------------------------------
  # Commit (requires prior reserve on the same line)
  # -------------------------------------------------------
  test "commit decrements on_hand and reserved after a prior reserve" do
    call_policy(action: :reserve)
    result = call_policy(action: :commit)

    assert_equal :committed, result[:results][0][:result]
    b = @balance.reload
    assert_equal 8, b.on_hand
    assert_equal 0, b.reserved
    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "commit", quantity: 2)
  end

  test "commit is safe to call twice: second call is blocked because open reserve is zero" do
    call_policy(action: :reserve)
    call_policy(action: :commit)
    result2 = call_policy(action: :commit)

    # After commit, reserved_qty_for_line = reserve(2) - committed(2) = 0 < qty(2) → blocked
    assert_equal :blocked_no_prior_line_reserve, result2[:results][0][:result]
    assert_equal 8, @balance.reload.on_hand  # unchanged after second call
  end

  test "commit returns blocked_no_prior_line_reserve when no reserve InventoryAction exists for line" do
    result = call_policy(action: :commit)

    assert_equal :blocked_no_prior_line_reserve, result[:results][0][:result]
    assert_equal 10, @balance.reload.on_hand
    refute InventoryAction.exists?(order_line_id: @line.id, action_type: "commit")
  end

  # -------------------------------------------------------
  # Release (requires prior reserve on the same line)
  # -------------------------------------------------------
  test "release decrements reserved after a prior reserve" do
    call_policy(action: :reserve)
    result = call_policy(action: :release)

    assert_equal :released, result[:results][0][:result]
    assert_equal 0, @balance.reload.reserved
    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "release", quantity: 2)
  end

  test "release returns blocked_no_prior_line_reserve when no reserve InventoryAction exists for line" do
    result = call_policy(action: :release)

    assert_equal :blocked_no_prior_line_reserve, result[:results][0][:result]
    refute InventoryAction.exists?(order_line_id: @line.id, action_type: "release")
  end

  # -------------------------------------------------------
  # Missing SKU
  # -------------------------------------------------------
  test "returns missing_sku result when order line has no sku" do
    no_sku_line = OrderLine.create!(order: @order, sku_id: nil, quantity: 1, idempotency_key: "no-sku-line-1")

    result = call_policy(line_actions: [{ order_line: no_sku_line, action: :reserve }])

    assert_equal :missing_sku, result[:results][0][:result]
    assert_equal no_sku_line.id, result[:results][0][:order_line_id]
  end

  # -------------------------------------------------------
  # line_actions parameter
  # -------------------------------------------------------
  test "line_actions parameter targets specific lines with specific actions" do
    identity2 = StockIdentity.create!
    sku2      = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0, stock_identity: identity2)
    InventoryBalance.create!(stock_identity: identity2, sku: sku2, on_hand: 5, reserved: 0)
    line2 = OrderLine.create!(order: @order, sku: sku2, quantity: 1, idempotency_key: "line-2")

    result = call_policy(
      line_actions: [
        { order_line: @line, action: :reserve },
        { order_line: line2, action: :reserve }
      ],
      prefix: "tiktok:order:TT-001-v2"
    )

    assert_equal 2, result[:results].size
    assert_equal :reserved, result[:results][0][:result]
    assert_equal :reserved, result[:results][1][:result]
    assert InventoryAction.exists?(order_line_id: @line.id, action_type: "reserve")
    assert InventoryAction.exists?(order_line_id: line2.id, action_type: "reserve")
  end

  # -------------------------------------------------------
  # Return structure
  # -------------------------------------------------------
  test "return hash includes ok, order_id, channel, and results" do
    result = call_policy(action: :reserve)

    assert result[:ok]
    assert_equal @order.id, result[:order_id]
    assert_equal "tiktok", result[:channel]
    assert_instance_of Array, result[:results]
    assert_equal @order.external_order_id, result[:external_order_id]
  end
end

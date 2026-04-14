# test/services/inventory_flow_test.rb
require "test_helper"
require "stringio"

class InventoryFlowTest < ActiveSupport::TestCase
  # ------------------------------------------------------------
  # Ruby-only stubs/spies (no mocha needed)
  # ------------------------------------------------------------

  def with_instance_method_override(klass, method_name, replacement_proc)
    original = klass.instance_method(method_name)

    klass.define_method(method_name) do |*args, **kwargs, &blk|
      replacement_proc.call(*args, **kwargs, &blk)
    end

    yield
  ensure
    klass.define_method(method_name, original)
  end

  def with_singleton_method_override(klass, method_name, replacement_proc)
    original = klass.method(method_name)

    klass.define_singleton_method(method_name) do |*args, **kwargs, &blk|
      replacement_proc.call(*args, **kwargs, &blk)
    end

    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end

  # Capture Rails.logger output for assertions.
  def capture_logs
    old_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old_logger
  end

  def setup
    @shop_tiktok = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @shop_lazada = Shop.create!(channel: "lazada", shop_code: "lz1", name: "LZ", active: true)

    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3)
    @balance = @sku.create_inventory_balance!(on_hand: 10, reserved: 0)
  end

  # -------------------------
  # Availability contract
  # -------------------------
  test "store_available ignores frozen; online_available becomes 0 when frozen" do
    assert_equal 10, @sku.store_available
    assert_equal 7,  @sku.online_available # 10 - 0 - 3

    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")

    assert_equal 10, @sku.reload.store_available
    assert_equal 0,  @sku.reload.online_available
  end

  # -------------------------
  # Reserve
  # -------------------------
  test "reserve success increases reserved and creates inventory_action (online buffer honored)" do
    res = Inventory::Reserve.call!(sku: @sku, quantity: 2, idempotency_key: "k-res-1", meta: {})
    assert_equal :reserved, res

    assert_equal 2, @balance.reload.reserved
    assert InventoryAction.exists?(idempotency_key: "k-res-1", action_type: "reserve")
    assert_nil @balance.reload.frozen_at

    # online_available = (10 - 2) - 3 = 5
    assert_equal 5, @sku.reload.online_available
    # store_available = on_hand - reserved = 8
    assert_equal 8, @sku.reload.store_available
  end

  test "reserve is idempotent" do
    res1 = Inventory::Reserve.call!(sku: @sku, quantity: 1, idempotency_key: "k-res-dup", meta: {})
    res2 = Inventory::Reserve.call!(sku: @sku, quantity: 1, idempotency_key: "k-res-dup", meta: {})

    assert_equal :reserved, res1
    assert_equal :already_applied, res2
    assert_equal 1, @balance.reload.reserved
  end

  test "reserve not enough stock freezes and does not create reserve action" do
    # online_available = 10 - 0 - 3 = 7; reserve 8 should freeze
    res = Inventory::Reserve.call!(sku: @sku, quantity: 8, idempotency_key: "k-res-2", meta: {})
    assert_equal :not_enough_stock, res

    b = @balance.reload
    assert b.frozen_now?
    assert_equal "not_enough_stock", b.freeze_reason
    refute InventoryAction.exists?(idempotency_key: "k-res-2", action_type: "reserve")

    assert_equal 0, @sku.reload.online_available
    assert_equal 10, @sku.reload.store_available # store unaffected
  end

  test "reserve returns :frozen when already frozen" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")

    res = Inventory::Reserve.call!(sku: @sku, quantity: 1, idempotency_key: "k-res-3", meta: {})
    assert_equal :frozen, res
    refute InventoryAction.exists?(idempotency_key: "k-res-3", action_type: "reserve")
  end

  # -------------------------
  # Commit (POS/store contract)
  # -------------------------
  test "commit decreases on_hand and reserved" do
    Inventory::Reserve.call!(sku: @sku, quantity: 2, idempotency_key: "k-res-4", meta: {})
    res = Inventory::Commit.call!(sku: @sku, quantity: 2, idempotency_key: "k-com-1", meta: {})

    assert_equal :committed, res
    b = @balance.reload
    assert_equal 8, b.on_hand
    assert_equal 0, b.reserved
    assert InventoryAction.exists?(idempotency_key: "k-com-1", action_type: "commit")
  end

  test "commit is idempotent" do
    Inventory::Reserve.call!(sku: @sku, quantity: 1, idempotency_key: "k-res-5", meta: {})

    res1 = Inventory::Commit.call!(sku: @sku, quantity: 1, idempotency_key: "k-com-dup", meta: {})
    res2 = Inventory::Commit.call!(sku: @sku, quantity: 1, idempotency_key: "k-com-dup", meta: {})

    assert_equal :committed, res1
    assert_equal :already_applied, res2

    b = @balance.reload
    assert_equal 9, b.on_hand
    assert_equal 0, b.reserved
  end

  test "commit raises if on_hand would go negative" do
    assert_raises(Inventory::Commit::OnHandWouldGoNegative) do
      Inventory::Commit.call!(sku: @sku, quantity: 999, idempotency_key: "k-com-2", meta: {})
    end
  end

  test "commit while frozen is allowed (POS must not be blocked) and logs event" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")

    logs = capture_logs do
      res = Inventory::Commit.call!(sku: @sku, quantity: 1, idempotency_key: "k-com-frozen", meta: { source: "pos" })
      assert_equal :committed, res
    end

    assert_includes logs, "inventory.commit.while_frozen"
  end

  # -------------------------
  # Release + UnfreezeIfResolved
  # -------------------------
  test "release decreases reserved and can auto-unfreeze when resolved at boundary (online_available becomes 0)" do
    # raw_available = 10 - 7 = 3; buffer=3 => online_if_unfrozen = 0 (resolved boundary)
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock", reserved: 7, on_hand: 10)

    res = Inventory::Release.call!(sku: @sku, quantity: 1, idempotency_key: "k-rel-1", meta: {})
    assert_equal :released, res

    b = @balance.reload
    assert_equal 6, b.reserved
    assert_nil b.frozen_at
    assert_nil b.freeze_reason
    assert InventoryAction.exists?(idempotency_key: "k-rel-1", action_type: "release")

    # online_available now = (10 - 6) - 3 = 1
    assert_equal 1, @sku.reload.online_available
  end

  test "UnfreezeIfResolved unfreezes when online_available_if_unfrozen == 0 (>=0 boundary)" do
    # raw_available=3, buffer=3 => online_if_unfrozen=0
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock", on_hand: 4, reserved: 1)

    res = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "test")
    assert_equal :unfrozen, res
    assert_nil @balance.reload.frozen_at
    assert_nil @balance.reload.freeze_reason
  end

  test "UnfreezeIfResolved returns :still_problematic when online_available_if_unfrozen < 0" do
    # on_hand=3 reserved=1 buffer=3 => raw=2 online_if_unfrozen=-1
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock", on_hand: 3, reserved: 1)

    res = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "test")
    assert_equal :still_problematic, res
    assert @balance.reload.frozen_now?
  end

  test "release does not auto-unfreeze when manual freeze" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "manual", reserved: 7, on_hand: 10)

    res = Inventory::Release.call!(sku: @sku, quantity: 2, idempotency_key: "k-rel-2", meta: {})
    assert_equal :released, res

    b = @balance.reload
    assert_equal 5, b.reserved
    assert b.frozen_now?
    assert_equal "manual", b.freeze_reason
  end

  # -------------------------
  # ReturnScan
  # -------------------------
  test "return_scan increases on_hand, creates records, and can auto-unfreeze" do
    order = Order.create!(channel: "tiktok", shop: @shop_tiktok, external_order_id: "O1", status: "delivered")
    line  = OrderLine.create!(order: order, sku: @sku, quantity: 1, idempotency_key: "line-1")
    ship  = ReturnShipment.create!(channel: "tiktok", shop: @shop_tiktok, order: order, external_order_id: "O1", status_store: "pending_scan")

    # freeze first: on_hand=3 reserved=1 buffer=3 => online_if_unfrozen=-1
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock", on_hand: 3, reserved: 1)

    res = Inventory::ReturnScan.call!(
      return_shipment: ship,
      order_line: line,
      quantity: 1,
      idempotency_key: "k-ret-1",
      meta: { by: "scanner" }
    )
    assert_equal :returned, res

    b = @balance.reload
    assert_equal 4, b.on_hand
    assert_nil b.frozen_at
    assert_nil b.freeze_reason

    assert ::ReturnScan.exists?(idempotency_key: "k-ret-1")
    assert InventoryAction.exists?(idempotency_key: "k-ret-1", action_type: "return_scan")
    assert StockMovement.exists?(reason: "return_scan")
  end

  test "return_scan is idempotent" do
    order = Order.create!(channel: "tiktok", shop: @shop_tiktok, external_order_id: "O2", status: "delivered")
    line  = OrderLine.create!(order: order, sku: @sku, quantity: 1, idempotency_key: "line-2")
    ship  = ReturnShipment.create!(channel: "tiktok", shop: @shop_tiktok, order: order, external_order_id: "O2", status_store: "pending_scan")

    res1 = Inventory::ReturnScan.call!(return_shipment: ship, order_line: line, quantity: 1, idempotency_key: "k-ret-dup", meta: {})
    res2 = Inventory::ReturnScan.call!(return_shipment: ship, order_line: line, quantity: 1, idempotency_key: "k-ret-dup", meta: {})

    assert_equal :returned, res1
    assert_equal :already_applied, res2
  end

  # -------------------------
  # StockIn
  # -------------------------
  test "stock_in increases on_hand, creates movement/action, and can auto-unfreeze" do
    # freeze first: on_hand=3 reserved=1 buffer=3 => online_if_unfrozen=-1
    @balance.update!(on_hand: 3, reserved: 1, frozen_at: Time.current, freeze_reason: "not_enough_stock")

    res = Inventory::StockIn.call!(
      sku: @sku,
      quantity: 1,
      idempotency_key: "k-stockin-1",
      meta: { source: "pos" }
    )
    assert_equal :stocked_in, res

    b = @balance.reload
    assert_equal 4, b.on_hand
    assert_nil b.frozen_at
    assert_nil b.freeze_reason

    assert InventoryAction.exists?(idempotency_key: "k-stockin-1", action_type: "stock_in")
    assert StockMovement.exists?(reason: "stock_in")
  end

  test "stock_in is idempotent" do
    res1 = Inventory::StockIn.call!(sku: @sku, quantity: 2, idempotency_key: "k-stockin-dup", meta: {})
    res2 = Inventory::StockIn.call!(sku: @sku, quantity: 2, idempotency_key: "k-stockin-dup", meta: {})

    assert_equal :stocked_in, res1
    assert_equal :already_applied, res2
  end

  # -------------------------
  # Buffer change -> unfreeze (Sku callback)
  # -------------------------
  test "buffer change triggers auto-unfreeze when online_available_if_unfrozen becomes >= 0 (boundary ok)" do
    # on_hand=3 reserved=1 buffer=3 => online_if_unfrozen=-1 (frozen)
    @balance.update!(on_hand: 3, reserved: 1, frozen_at: Time.current, freeze_reason: "not_enough_stock")

    # reduce buffer => online_if_unfrozen becomes 0 -> should unfreeze
    @sku.update!(buffer_quantity: 2)

    b = @balance.reload
    assert_nil b.frozen_at
    assert_nil b.freeze_reason
  end

  # -------------------------
  # Manual freeze/unfreeze
  # -------------------------
  test "manual freeze never auto-unfreezes even when online_available_if_unfrozen becomes >= 0" do
    assert_equal 7, @sku.online_available

    Inventory::ManualFreeze.call!(sku: @sku)
    assert_equal 0, @sku.reload.online_available
    assert_equal "manual", @balance.reload.freeze_reason
    assert @balance.reload.frozen_now?

    @balance.update!(on_hand: 999, reserved: 0)

    res = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "test")
    assert_equal :manual_freeze, res
    assert @balance.reload.frozen_now?
  end

  test "manual unfreeze requires manual freeze" do
    res1 = Inventory::ManualUnfreeze.call!(sku: @sku)
    assert_equal :not_frozen, res1

    Inventory::ManualFreeze.call!(sku: @sku)

    res2 = Inventory::ManualUnfreeze.call!(sku: @sku)
    assert_equal :manual_unfrozen, res2
    refute @balance.reload.frozen_now?
  end

  # -------------------------
  # StockSync skip logic + online availability
  # -------------------------
  test "StockSync::PushSku uses online_available and skips when same" do
    available = @sku.online_available
    @balance.update_columns(last_pushed_available: available)

    logs = capture_logs do
      res = StockSync::PushSku.call!(sku: @sku, reason: "test")
      assert_equal available, res
    end

    assert_includes logs, "stock_sync.push_marketplace.skip"
  end

  test "StockSync::PushSku frozen forces available=0" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")

    res = StockSync::PushSku.call!(sku: @sku, reason: "test", force: true)

    assert_equal 0, res
  end

  test "InventoryBalance after_commit enqueues SyncStockJob when relevant fields change" do
    assert_enqueued_with(job: SyncStockJob) do
      @balance.update!(on_hand: 11)
    end

    assert_enqueued_with(job: SyncStockJob) do
      @balance.update!(reserved: 1)
    end
  end
end
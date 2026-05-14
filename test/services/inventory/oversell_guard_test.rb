# test/services/inventory/oversell_guard_test.rb
require "test_helper"

class Inventory::OversellGuardTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0, stock_identity: @identity)
    # Start with NO shortfall: reserved(5) <= on_hand(10)
    @balance  = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 5)

    @order = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "TT-001", status: "IN_TRANSIT")
    @line  = OrderLine.create!(order: @order, sku: @sku, quantity: 5, idempotency_key: "line-1")

    # Open reserve of 5 for @line so the allocator has something to work with
    InventoryAction.create!(
      sku: @sku, order_line_id: @line.id,
      action_type: "reserve", quantity: 5,
      idempotency_key: "reserve-1", meta: {}
    )
  end

  def call_guard(trigger: "test", key: "g-key-1")
    Inventory::OversellGuard.call!(sku: @sku, trigger: trigger, idempotency_key: key, meta: {})
  end

  # Introduce shortfall by reducing on_hand below reserved
  def introduce_shortfall(on_hand: 3)
    @balance.update!(on_hand: on_hand)  # reserved stays 5; shortfall = 5 - 3 = 2
  end

  # -------------------------------------------------------
  # No shortfall
  # -------------------------------------------------------
  test "returns :ok and creates no incident when reserved does not exceed on_hand" do
    result = call_guard

    assert result[:ok]
    assert_equal :ok, result[:result]
    assert_operator result[:shortfall_qty], :<=, 0
    assert_equal 0, OversellIncident.count
    refute @balance.reload.frozen_now?
  end

  # -------------------------------------------------------
  # Shortfall: incident creation + freeze
  # -------------------------------------------------------
  test "shortfall creates OversellIncident, freezes balance with reason 'oversold'" do
    introduce_shortfall

    result = call_guard(key: "g-key-2")

    assert_equal :incident_created, result[:result]
    assert_equal 2, result[:shortfall_qty]

    incident = OversellIncident.find(result[:oversell_incident_id])
    assert_equal "open", incident.status
    assert_equal 2, incident.shortfall_qty
    assert_equal @sku.id, incident.sku_id

    b = @balance.reload
    assert b.frozen_now?
    assert_equal "oversold", b.freeze_reason
  end

  # -------------------------------------------------------
  # Shortfall: FIFO allocation
  # -------------------------------------------------------
  test "shortfall creates OversellAllocation records via FIFO allocator" do
    introduce_shortfall  # shortfall = 2, @line has outstanding = 5

    call_guard(key: "g-key-3")

    assert_equal 1, OversellAllocation.count
    alloc = OversellAllocation.first
    assert_equal @line.id, alloc.order_line_id
    assert_equal 2, alloc.quantity   # takes only the shortfall, not the full outstanding
    assert_equal @sku.id, alloc.sku_id
  end

  # -------------------------------------------------------
  # Shortfall: ForceOversellZeroJob enqueued
  # -------------------------------------------------------
  test "shortfall enqueues ForceOversellZeroJob with the incident id" do
    introduce_shortfall

    assert_enqueued_with(job: ForceOversellZeroJob) do
      call_guard(key: "g-key-4")
    end

    job_args = enqueued_jobs.find { |j| j["job_class"] == "ForceOversellZeroJob" }
    incident_id = OversellIncident.first.id
    assert_includes job_args["arguments"], incident_id
  end

  # -------------------------------------------------------
  # Shortfall: reuses open incident on second call
  # -------------------------------------------------------
  test "second call with shortfall reuses existing open incident and returns :incident_reused" do
    introduce_shortfall

    result1 = call_guard(key: "g-key-5a")
    result2 = call_guard(key: "g-key-5b")

    assert_equal :incident_created, result1[:result]
    assert_equal :incident_reused,  result2[:result]

    assert_equal 1, OversellIncident.count
    assert_equal result1[:oversell_incident_id], result2[:oversell_incident_id]
  end

  test "second call refreshes OversellAllocation records (delete and recreate)" do
    introduce_shortfall

    call_guard(key: "g-key-6a")
    assert_equal 1, OversellAllocation.count

    # Reduce shortfall more — allocator will recalculate
    @balance.update!(on_hand: 4)  # shortfall now = 5 - 4 = 1

    call_guard(key: "g-key-6b")

    # Still one allocation but qty is now 1 (updated)
    assert_equal 1, OversellAllocation.count
    assert_equal 1, OversellAllocation.first.quantity
  end

  # -------------------------------------------------------
  # No shortfall: ForceOversellZeroJob NOT enqueued
  # -------------------------------------------------------
  test "no shortfall does not enqueue ForceOversellZeroJob" do
    assert_no_enqueued_jobs(only: ForceOversellZeroJob) do
      call_guard
    end
  end
end

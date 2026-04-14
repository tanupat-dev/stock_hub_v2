require "test_helper"

class InventoryAdjustTest < ActiveSupport::TestCase
  def setup
    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0)
    @balance = @sku.create_inventory_balance!(on_hand: 10, reserved: 7)
  end

  test "oversold adjust clamps reserved and freezes" do
    res = Inventory::Adjust.call!(
      sku: @sku,
      set_to: 5,
      idempotency_key: "adjust-1"
    )

    assert_equal :adjusted, res

    b = InventoryBalance.find_by!(sku_id: @sku.id)
    assert_equal 5, b.on_hand
    assert_equal 5, b.reserved
    assert b.frozen_at.present?
    assert_equal "oversold_adjust", b.freeze_reason
    assert_equal 0, b.raw_available
  end

  test "normal adjust without oversold" do
    res = Inventory::Adjust.call!(
      sku: @sku,
      set_to: 12,
      idempotency_key: "adjust-2"
    )

    assert_equal :adjusted, res

    b = @balance.reload
    assert_equal 12, b.on_hand
    assert_equal 7, b.reserved
    assert_equal 5, b.raw_available
  end

  test "oversold adjust creates incident and allocations (fifo)" do
    # สำคัญ: reset reserved ก่อน เพราะ setup ใส่ 7 มา
    @balance.update!(reserved: 0)

    shop = Shop.create!(channel: "tiktok", shop_code: "tt2", name: "TT2", active: true)
    order = Order.create!(channel: "tiktok", shop: shop, external_order_id: "OX", status: "paid")
    line1 = OrderLine.create!(order: order, sku: @sku, quantity: 4, idempotency_key: "ol-1")
    line2 = OrderLine.create!(order: order, sku: @sku, quantity: 3, idempotency_key: "ol-2")

    Inventory::Reserve.call!(sku: @sku, quantity: 4, idempotency_key: "adj-res-1", order_line: line1, meta: {})
    sleep 0.01
    Inventory::Reserve.call!(sku: @sku, quantity: 3, idempotency_key: "adj-res-2", order_line: line2, meta: {})

    # reserved = 7 now; set_to 5 => shortfall 2
    res = Inventory::Adjust.call!(sku: @sku, set_to: 5, idempotency_key: "adjust-oversold-1")
    assert_equal :adjusted, res

    incident = OversellIncident.find_by!(idempotency_key: "adjust-oversold-1")
    assert_equal @sku.id, incident.sku_id
    assert_equal 2, incident.shortfall_qty
    assert_equal "open", incident.status

    allocs = incident.oversell_allocations.order(:created_at).to_a
    assert_equal 1, allocs.length
    assert_equal line1.id, allocs[0].order_line_id
    assert_equal 2, allocs[0].quantity
  end
end
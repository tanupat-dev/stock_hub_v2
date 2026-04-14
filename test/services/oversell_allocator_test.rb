require "test_helper"

class OversellAllocatorTest < ActiveSupport::TestCase
  def setup
    @shop = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0)
    @sku.create_inventory_balance!(on_hand: 10, reserved: 0)

    @order1 = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "O1", status: "paid")
    @line1  = OrderLine.create!(order: @order1, sku: @sku, quantity: 3, idempotency_key: "l1")

    @order2 = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "O2", status: "paid")
    @line2  = OrderLine.create!(order: @order2, sku: @sku, quantity: 3, idempotency_key: "l2")

    # Reserve line1 first, then line2 (FIFO should hit line1 first)
    Inventory::Reserve.call!(sku: @sku, quantity: 3, idempotency_key: "res1", order_line: @line1, meta: {})
    sleep 0.01
    Inventory::Reserve.call!(sku: @sku, quantity: 3, idempotency_key: "res2", order_line: @line2, meta: {})
  end

  test "allocates shortfall FIFO by first reserve time" do
    allocs = Inventory::OversellAllocator.call!(sku: @sku, shortfall_qty: 4)

    assert_equal 2, allocs.length
    assert_equal({ order_line_id: @line1.id, qty: 3 }, allocs[0])
    assert_equal({ order_line_id: @line2.id, qty: 1 }, allocs[1])
  end
end
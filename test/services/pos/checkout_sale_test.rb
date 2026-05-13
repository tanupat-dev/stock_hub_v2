# test/services/pos/checkout_sale_test.rb
require "test_helper"

class Pos::CheckoutSaleTest < ActiveSupport::TestCase
  def setup
    @shop     = Shop.create!(channel: "pos", shop_code: "pos1", name: "POS Store", active: true)
    @identity = StockIdentity.create!
    @sku      = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0, stock_identity: @identity)
    @balance  = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 0)

    @sale = PosSale.create!(
      shop: @shop,
      sale_number: "S001",
      status: "cart",
      idempotency_key: "sale-ik-1",
      item_count: 0
    )
    @line = PosSaleLine.create!(
      pos_sale: @sale,
      sku: @sku,
      status: "active",
      sku_code_snapshot: @sku.code,
      idempotency_key: "line-1",
      quantity: 2
    )
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------
  test "checkout decrements on_hand and marks sale as checked_out" do
    result = Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-1", meta: {})

    assert_equal "checked_out", result.status
    assert_not_nil result.checked_out_at
    assert_equal 8, @balance.reload.on_hand
    assert_equal 0, @balance.reload.reserved   # CommitPos does not touch reserved
    assert InventoryAction.exists?(action_type: "commit")
  end

  test "checkout stores the idempotency_key in sale meta" do
    Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-meta-test", meta: {})

    assert_equal "checkout-meta-test", @sale.reload.meta["checkout_idempotency_key"]
  end

  test "checkout with multiple lines commits each line individually" do
    identity2 = StockIdentity.create!
    sku2      = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0, stock_identity: identity2)
    InventoryBalance.create!(stock_identity: identity2, sku: sku2, on_hand: 5, reserved: 0)
    PosSaleLine.create!(
      pos_sale: @sale, sku: sku2, status: "active",
      sku_code_snapshot: sku2.code, idempotency_key: "line-2", quantity: 3
    )

    Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-2", meta: {})

    assert_equal 8, @balance.reload.on_hand          # SKU1: 10 - 2
    assert_equal 2, InventoryBalance.find_by(stock_identity: identity2).on_hand  # SKU2: 5 - 3
  end

  # -------------------------------------------------------
  # Idempotency (replay)
  # -------------------------------------------------------
  test "checkout is idempotent: same idempotency_key on checked_out sale returns sale without error" do
    Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-dup", meta: {})

    # Second call with same key — should be a no-op replay
    result = Pos::CheckoutSale.call!(sale: @sale.reload, idempotency_key: "checkout-dup", meta: {})

    assert_equal "checked_out", result.status
    # on_hand should not have decreased a second time
    assert_equal 8, @balance.reload.on_hand
    assert_equal 1, InventoryAction.where(action_type: "commit").count
  end

  # -------------------------------------------------------
  # Guard: sale must be cart
  # -------------------------------------------------------
  test "raises SaleNotCart if sale is already checked_out with different idempotency_key" do
    Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "first-checkout", meta: {})

    assert_raises(Pos::CheckoutSale::SaleNotCart) do
      Pos::CheckoutSale.call!(sale: @sale.reload, idempotency_key: "different-key", meta: {})
    end
  end

  test "raises SaleNotCart if sale is voided" do
    @sale.update!(status: "voided")

    assert_raises(Pos::CheckoutSale::SaleNotCart) do
      Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-voided", meta: {})
    end
  end

  # -------------------------------------------------------
  # Guard: sale must have active lines
  # -------------------------------------------------------
  test "raises EmptySale if no active lines" do
    @line.update!(status: "voided")

    assert_raises(Pos::CheckoutSale::EmptySale) do
      Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-empty", meta: {})
    end
  end

  # -------------------------------------------------------
  # Guard: insufficient stock
  # -------------------------------------------------------
  test "raises InsufficientStock when on_hand is less than requested quantity" do
    @balance.update!(on_hand: 1)

    assert_raises(Pos::CheckoutSale::InsufficientStock) do
      Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-insufficient", meta: {})
    end

    # on_hand must remain unchanged after the error
    assert_equal 1, @balance.reload.on_hand
  end

  test "raises InsufficientStock when on_hand is zero" do
    @balance.update!(on_hand: 0)

    assert_raises(Pos::CheckoutSale::InsufficientStock) do
      Pos::CheckoutSale.call!(sale: @sale, idempotency_key: "checkout-zero", meta: {})
    end
  end
end

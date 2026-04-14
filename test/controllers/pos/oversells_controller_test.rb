require "test_helper"
require "ostruct"

class Pos::OversellsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @pos_key = "test-pos-key"
    @shop = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)
    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 0)
    @sku.create_inventory_balance!(on_hand: 10, reserved: 0)
  end

  def with_pos_credentials
    app = Rails.application
    original = app.method(:credentials)
    fake = OpenStruct.new(pos_api_key: @pos_key)
    app.define_singleton_method(:credentials) { fake }
    yield
  ensure
    app.define_singleton_method(:credentials) { original.call }
  end

  test "GET /pos/oversells returns open incidents with allocations" do
    order = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "O1", status: "paid")
    line  = OrderLine.create!(order: order, sku: @sku, quantity: 7, idempotency_key: "l1")
    Inventory::Reserve.call!(sku: @sku, quantity: 7, idempotency_key: "r1", order_line: line, meta: {})

    Inventory::Adjust.call!(sku: @sku, set_to: 5, idempotency_key: "pos-oversold-1", meta: { by: "count" })

    with_pos_credentials do
      get "/pos/oversells", headers: { "X-POS-KEY" => @pos_key }
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal true, body["ok"]
      assert body["incidents"].length >= 1
      first = body["incidents"][0]
      assert_equal 2, first["shortfall_qty"]
      assert_equal "open", first["status"]
      assert first["allocations"].length >= 1
    end
  end
end
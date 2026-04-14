# frozen_string_literal: true

require "test_helper"
require "json"
require "ostruct"

class Pos::ReturnsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @pos_key = "test-pos-key"
    @shop = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)

    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3)
    @balance = @sku.create_inventory_balance!(on_hand: 3, reserved: 0)

    @order = Order.create!(channel: "tiktok", shop: @shop, external_order_id: "O1", status: "delivered")
    @line = OrderLine.create!(order: @order, sku: @sku, quantity: 1, idempotency_key: "line-1")

    @shipment = ReturnShipment.create!(
      channel: "tiktok",
      shop: @shop,
      order: @order,
      external_order_id: "O1",
      external_return_id: "R1",
      tracking_number: "TRACK1",
      status_store: "pending_scan"
    )
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

  test "POST /pos/returns/lookup unauthorized without X-POS-KEY" do
    with_pos_credentials do
      post "/pos/returns/lookup", params: { tracking_number: "TRACK1" }, as: :json
      assert_response :unauthorized

      body = JSON.parse(response.body)
      assert_equal false, body["ok"]
      assert_equal "Unauthorized", body["error"]
    end
  end

  test "POST /pos/returns/lookup finds shipment by tracking_number and returns order lines" do
    with_pos_credentials do
      post "/pos/returns/lookup",
           params: { tracking_number: "TRACK1" },
           headers: { "X-POS-KEY" => @pos_key },
           as: :json

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal true, body["ok"]
      assert_equal @shipment.id, body["return_shipment"]["id"]
      assert_equal "TRACK1", body["return_shipment"]["tracking_number"]

      lines = body["order_lines"]
      assert_equal 1, lines.length
      assert_equal @line.id, lines[0]["order_line_id"]
      assert_equal "SKU1", lines[0]["sku_code"]
      assert_equal "B1", lines[0]["barcode"]
      assert_equal 1, lines[0]["qty_ordered"]
      assert_equal 0, lines[0]["qty_returned"]
      assert_equal 1, lines[0]["qty_pending"]
    end
  end

  test "POST /pos/returns/scan increases on_hand and can mark shipment received_scanned when fully returned" do
    with_pos_credentials do
      post "/pos/returns/scan",
           params: {
             return_shipment_id: @shipment.id,
             order_line_id: @line.id,
             barcode: "B1",
             quantity: 1,
             idempotency_key: "pos:test:returnscan:1"
           },
           headers: { "X-POS-KEY" => @pos_key },
           as: :json

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal true, body["ok"]
      assert_equal "returned", body["result"]
      assert_equal "received_scanned", body["return_shipment_status_store"]

      # inventory increased
      assert_equal 4, body["after"]["balance"]["on_hand"]
      assert_equal 4, @balance.reload.on_hand

      # snapshots exist
      assert body["before"].is_a?(Hash)
      assert body["after"].is_a?(Hash)

      # return record + action exist
      assert ::ReturnScan.exists?(idempotency_key: "pos:test:returnscan:1")
      assert InventoryAction.exists?(idempotency_key: "pos:test:returnscan:1", action_type: "return_scan")
      assert StockMovement.exists?(reason: "return_scan")
    end
  end

  test "POST /pos/returns/scan rejects SKU mismatch for order_line" do
    other = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0)
    other.create_inventory_balance!(on_hand: 1, reserved: 0)

    with_pos_credentials do
      post "/pos/returns/scan",
           params: {
             return_shipment_id: @shipment.id,
             order_line_id: @line.id,
             barcode: "B2",
             quantity: 1,
             idempotency_key: "pos:test:returnscan:mismatch"
           },
           headers: { "X-POS-KEY" => @pos_key },
           as: :json

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_equal false, body["ok"]
      assert_equal "SKU mismatch for this order_line", body["error"]
    end
  end
end
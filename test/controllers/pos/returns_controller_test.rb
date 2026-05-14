# frozen_string_literal: true

require "test_helper"
require "json"

class Pos::ReturnsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @pos_key = "test-pos-key"
    @shop = Shop.create!(channel: "tiktok", shop_code: "tt1", name: "TT", active: true)

    @identity = StockIdentity.create!
    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3, stock_identity: @identity)
    @balance = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 3, reserved: 0)

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

    @shipment_line = ReturnShipmentLine.create!(
      return_shipment: @shipment,
      order_line: @line,
      sku: @sku,
      sku_code_snapshot: @sku.code,
      qty_returned: 1
    )
  end

  def with_pos_credentials
    app = Rails.application
    original = app.method(:credentials)

    fake = { pos: { key: @pos_key } }

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

  test "POST /pos/returns/lookup finds shipment by tracking_number and returns return_lines" do
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

      lines = body["return_lines"]
      assert_equal 1, lines.length
      assert_equal @line.id, lines[0]["order_line_id"]
      assert_equal "SKU1", lines[0]["sku_code"]
      assert_equal "B1", lines[0]["barcode"]
      assert_equal 1, lines[0]["qty_requested"]
      assert_equal 0, lines[0]["qty_scanned"]
      assert_equal 1, lines[0]["qty_pending"]
    end
  end

  test "POST /pos/returns/scan increases on_hand and can mark shipment received_scanned when fully returned" do
    with_pos_credentials do
      post "/pos/returns/scan",
           params: {
             return_shipment_id: @shipment.id,
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
      assert_equal "received_scanned", body["return_shipment"]["derived_status_store"]

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
    # Shipment line says "SKU2" (no sku_id set), but order_line has SKU1
    # Controller finds shipment line by code match, then detects order_line.sku != scanned sku
    other = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 0)
    ReturnShipmentLine.create!(
      return_shipment: @shipment,
      order_line: @line,
      sku_code_snapshot: "SKU2",
      qty_returned: 1
    )

    with_pos_credentials do
      post "/pos/returns/scan",
           params: {
             return_shipment_id: @shipment.id,
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

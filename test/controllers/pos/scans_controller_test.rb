# frozen_string_literal: true

require "test_helper"
require "json"
require "ostruct"
require "stringio"

class Pos::ScansControllerTest < ActionDispatch::IntegrationTest
  def setup
    @sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3)
    @balance = @sku.create_inventory_balance!(on_hand: 2, reserved: 0)
    @pos_key = "test-pos-key"
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

  def capture_logs
    old_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old_logger
  end

  test "POST /pos/scans unauthorized without X-POS-KEY" do
    with_pos_credentials do
      post "/pos/scans", params: { barcode: "B1", quantity: 1 }, as: :json
      assert_response :unauthorized

      body = JSON.parse(response.body)
      assert_equal false, body["ok"]
      assert_equal "Unauthorized", body["error"]
    end
  end

  test "POST /pos/scans commits stock and returns before/after snapshots" do
    with_pos_credentials do
      logs = capture_logs do
        post "/pos/scans",
             params: { barcode: "B1", quantity: 1, idempotency_key: "pos:test:scan:1" },
             headers: { "X-POS-KEY" => @pos_key },
             as: :json
      end

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal true, body["ok"]
      assert_equal "committed", body["result"]
      assert_equal "pos:test:scan:1", body["idempotency_key"]

      # before/after present
      assert body["before"].is_a?(Hash)
      assert body["after"].is_a?(Hash)

      # state changes
      assert_equal 2, body["before"]["balance"]["on_hand"]
      assert_equal 1, body["after"]["balance"]["on_hand"]

      # store_available decreased, online_available respects buffer
      # before: raw=2, buffer=3 => online=0
      assert_equal 2, body["before"]["store_available"]
      assert_equal 0, body["before"]["online_available"]

      # after: raw=1, buffer=3 => online=0
      assert_equal 1, body["after"]["store_available"]
      assert_equal 0, body["after"]["online_available"]

      # structured log emitted
      assert_includes logs, "pos.scan.commit"
      assert_includes logs, "\"sku\":\"SKU1\""
    end
  end

  test "POST /pos/scans allows commit while frozen (POS must not be blocked)" do
    @balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")

    with_pos_credentials do
      post "/pos/scans",
           params: { barcode: "B1", quantity: 1, idempotency_key: "pos:test:scan:frozen" },
           headers: { "X-POS-KEY" => @pos_key },
           as: :json

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal true, body["ok"]
      assert_equal "committed", body["result"]

      # still commits
      assert_equal 1, body["after"]["balance"]["on_hand"]

      # frozen remains (freeze is for marketplace; POS commit does not auto-unfreeze here)
      assert body["after"]["balance"]["frozen_at"].present?
      assert_equal "not_enough_stock", body["after"]["balance"]["freeze_reason"]
    end
  end

  test "POST /pos/scans returns 422 when on_hand would go negative" do
    with_pos_credentials do
      post "/pos/scans",
           params: { barcode: "B1", quantity: 999, idempotency_key: "pos:test:scan:neg" },
           headers: { "X-POS-KEY" => @pos_key },
           as: :json

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_equal false, body["ok"]
      assert_equal "Not enough stock", body["error"]
    end
  end
end
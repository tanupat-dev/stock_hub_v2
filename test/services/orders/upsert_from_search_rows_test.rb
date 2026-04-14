# test/services/orders/upsert_from_search_rows_test.rb
require "test_helper"

class OrdersUpsertFromSearchRowsTest < ActiveSupport::TestCase
  def setup
    suffix = SecureRandom.hex(4)

    @sku = Sku.create!(code: "SKU1_#{suffix}", barcode: "B1_#{suffix}", buffer_quantity: 0)
    @sku.create_inventory_balance!(on_hand: 10, reserved: 0)

    @app = TiktokApp.create!(
      code: "tiktok_1_#{suffix}",
      auth_region: "ROW",
      service_id: "S1",
      app_key: "K",
      app_secret: "S",
      open_api_host: "https://open-api.tiktokglobalshop.com",
      active: true
    )

    @cred = TiktokCredential.create!(
      tiktok_app: @app,
      open_id: "OID_#{suffix}",
      user_type: 1,
      seller_name: "Seller",
      seller_base_region: "TH",
      access_token: "AT_#{suffix}",
      access_token_expires_at: 1.hour.from_now,
      refresh_token: "RT_#{suffix}",
      refresh_token_expires_at: 30.days.from_now,
      granted_scopes: [],
      active: true
    )

    @shop = Shop.create!(
      channel: "tiktok",
      shop_code: "tt_1_#{suffix}",
      name: "TT1",
      active: true,
      shop_cipher: "CIPHER_#{suffix}",
      tiktok_credential: @cred
    )

    SkuMapping.create!(
      channel: "tiktok",
      shop: @shop,
      external_sku: "red_iphone_256",
      sku: @sku
    )
  end

  test "polling same UNPAID order twice does not reserve twice" do
    rows = [
      {
        "id" => "O1",
        "status" => "UNPAID",
        "update_time" => 100,
        "create_time" => 90,
        "line_items" => [
          {
            "id" => "L1",
            "seller_sku" => "red_iphone_256",
            "quantity" => 1
          }
        ]
      }
    ]

    # รอบ 1
    Orders::UpsertFromSearchRows.call!(shop: @shop, rows: rows)

    # รอบ 2 (ซ้ำ)
    Orders::UpsertFromSearchRows.call!(shop: @shop, rows: rows)

    b = @sku.inventory_balance.reload

    # ต้อง reserve แค่ครั้งเดียว
    assert_equal 1, b.reserved

    # inventory_actions ไม่ควรมี idempotency ซ้ำ
    dups = InventoryAction.group(:idempotency_key).having("count(*) > 1").count
    assert_equal({}, dups)
  end
end
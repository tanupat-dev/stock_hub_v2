# test/services/marketplace/tiktok/orders/search_test.rb
# frozen_string_literal: true

require "test_helper"

class MarketplaceTiktokOrdersSearchTest < ActiveSupport::TestCase
  def setup
    suffix = SecureRandom.hex(4)

    @app =
      TiktokApp.create!(
        code: "tiktok_1_#{suffix}",
        auth_region: "ROW",
        service_id: "S1",
        app_key: "K",
        app_secret: "S",
        open_api_host: "https://open-api.tiktokglobalshop.com",
        active: true
      )

    @cred =
      TiktokCredential.create!(
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

    @shop =
      Shop.create!(
        channel: "tiktok",
        shop_code: "tt_1_#{suffix}",
        name: "TT1",
        active: true,
        shop_cipher: "CIPHER_#{suffix}",
        tiktok_credential: @cred
      )
  end

  test "returns rows and next_page_token from single page response" do
    fake_client = Object.new

    page1 = {
      "orders" => [
        { "id" => "O1", "status" => "UNPAID", "update_time" => 100 }
      ],
      "next_page_token" => "NEXT"
    }

    fake_client.define_singleton_method(:post) do |_path, query:, body:|
      page1
    end

    Marketplace::Tiktok::Client.stub(:new, fake_client) do
      resp =
        Marketplace::Tiktok::Orders::Search.call!(
          shop: @shop,
          update_time_ge: 1,
          update_time_lt: 999,
          page_size: 100,
          page_token: nil
        )

      # Structure contract
      assert resp.is_a?(Hash)
      assert resp.key?(:rows)
      assert resp.key?(:next_page_token)

      assert_equal 1, resp[:rows].size
      assert_equal "NEXT", resp[:next_page_token]
    end
  end
end
# frozen_string_literal: true

require "test_helper"

class PollTiktokOrdersJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    suffix = SecureRandom.hex(4)

    @tiktok_app =
      TiktokApp.create!(
        code: "tiktok_1_#{suffix}",
        auth_region: "ROW",
        service_id: "SVC1",
        app_key: "k",
        app_secret: "s",
        open_api_host: "https://open-api.tiktokglobalshop.com",
        active: true
      )

    @cred =
      TiktokCredential.create!(
        tiktok_app: @tiktok_app,
        open_id: "open_#{suffix}",
        user_type: 1,
        seller_name: "Seller",
        seller_base_region: "TH",
        access_token: "at_#{suffix}",
        access_token_expires_at: 1.hour.from_now,
        refresh_token: "rt_#{suffix}",
        refresh_token_expires_at: 30.days.from_now,
        granted_scopes: [],
        active: true
      )

    @shop =
      Shop.create!(
        channel: "tiktok",
        shop_code: "THLCJ4W23M_#{suffix}",
        name: "TikTok Shop 1",
        active: true,
        shop_cipher: "cipher_#{suffix}",
        tiktok_credential_id: @cred.id
      )
  end

  test "paginates with next_page_token and advances cursor to max update_time seen" do
    travel_to Time.zone.parse("2026-02-21 12:00:00") do
      # window_ge/lt expected (first run uses lookback)
      now_ts = Time.current.to_i
      expected_lt = now_ts - PollTiktokOrdersJob::SAFETY_LAG_SECONDS
      expected_ge = (now_ts - PollTiktokOrdersJob::FIRST_RUN_LOOKBACK_SECONDS) - PollTiktokOrdersJob::SAFETY_LAG_SECONDS

      # ให้ update_time อยู่ใน window จริง (ไม่ใช่ 1000/1100)
      t1 = expected_ge + 10
      t2 = expected_ge + 20

      calls = []
      upsert_calls = []

      search_stub = lambda do |shop:, update_time_ge:, update_time_lt:, page_size:, page_token: nil|
        calls << {
          shop_id: shop.id,
          ge: update_time_ge,
          lt: update_time_lt,
          page_size: page_size,
          page_token: page_token
        }

        assert_equal @shop.id, shop.id
        assert_equal expected_ge, update_time_ge
        assert_equal expected_lt, update_time_lt
        assert_equal PollTiktokOrdersJob::PAGE_SIZE, page_size

        if page_token.nil?
          {
            rows: [{ "id" => "O1", "update_time" => t1 }],
            next_page_token: "tok1"
          }
        else
          assert_equal "tok1", page_token
          {
            rows: [{ "id" => "O2", "update_time" => t2 }],
            next_page_token: nil
          }
        end
      end

      upsert_stub = lambda do |shop:, rows:|
        upsert_calls << { shop_id: shop.id, rows: rows }
        assert_equal @shop.id, shop.id
        assert rows.any?
      end

      Marketplace::Tiktok::Orders::Search.stub(:call!, search_stub) do
        Orders::UpsertFromSearchRows.stub(:call!, upsert_stub) do
          res = PollTiktokOrdersJob.perform_now(@shop.id)

          assert_equal true, res[:ok]
          assert_equal 2, res[:pages]
          assert_equal 2, res[:fetched]
          assert_equal t2, res[:cursor_written]

          @shop.reload
          assert_equal t2, @shop.last_seen_update_time
          assert_equal Time.zone.parse("2026-02-21 12:00:00"), @shop.last_polled_at

          assert_equal 2, calls.size
          assert_equal 2, upsert_calls.size
        end
      end
    end
  end

  test "when no rows returned, advances cursor to window_lt (covers window)" do
    travel_to Time.zone.parse("2026-02-21 12:00:00") do
      now_ts = Time.current.to_i
      expected_lt = now_ts - PollTiktokOrdersJob::SAFETY_LAG_SECONDS

      called = false

      search_stub = lambda do |shop:, update_time_ge:, update_time_lt:, page_size:, page_token: nil|
        called = true
        {
          rows: [],
          next_page_token: nil
        }
      end

      Marketplace::Tiktok::Orders::Search.stub(:call!, search_stub) do
        # ✅ ต้องไม่ถูกเรียกเมื่อ rows ว่าง
        Orders::UpsertFromSearchRows.stub(:call!, ->(**) { flunk "should not upsert on empty rows" }) do
          res = PollTiktokOrdersJob.perform_now(@shop.id)

          assert_equal true, res[:ok]
          assert_equal 1, res[:pages]
          assert_equal 0, res[:fetched]
          assert_equal expected_lt, res[:cursor_written]

          @shop.reload
          assert_equal expected_lt, @shop.last_seen_update_time
          assert_equal Time.zone.parse("2026-02-21 12:00:00"), @shop.last_polled_at
          assert called
        end
      end
    end
  end

  test "when window is empty (window_lt <= window_ge), does not call API and only updates last_polled_at" do
    travel_to Time.zone.parse("2026-02-21 12:00:00") do
      # make cursor so new window becomes empty
      now_ts = Time.current.to_i
      @shop.update!(last_seen_update_time: now_ts)

      Marketplace::Tiktok::Orders::Search.stub(:call!, ->(**) { flunk "should not call API" }) do
        Orders::UpsertFromSearchRows.stub(:call!, ->(**) { flunk "should not upsert" }) do
          res = PollTiktokOrdersJob.perform_now(@shop.id)

          assert_equal true, res[:ok]
          assert_equal 0, res[:pages]
          assert_equal 0, res[:fetched]

          @shop.reload
          assert_equal Time.zone.parse("2026-02-21 12:00:00"), @shop.last_polled_at
          # cursor should remain what it was
          assert_equal now_ts, @shop.last_seen_update_time
        end
      end
    end
  end

  test "raises when exceeded MAX_PAGES" do
    # shrink MAX_PAGES for test speed
    old = PollTiktokOrdersJob::MAX_PAGES
    PollTiktokOrdersJob.send(:remove_const, :MAX_PAGES)
    PollTiktokOrdersJob.const_set(:MAX_PAGES, 2)

    travel_to Time.zone.parse("2026-02-21 12:00:00") do
      search_stub = lambda do |shop:, update_time_ge:, update_time_lt:, page_size:, page_token: nil|
        { rows: [], next_page_token: "still_more" } # never ends
      end

      Marketplace::Tiktok::Orders::Search.stub(:call!, search_stub) do
        Orders::UpsertFromSearchRows.stub(:call!, ->(**) { 0 }) do
          assert_raises(RuntimeError) do
            PollTiktokOrdersJob.perform_now(@shop.id)
          end
        end
      end
    end
  ensure
    PollTiktokOrdersJob.send(:remove_const, :MAX_PAGES)
    PollTiktokOrdersJob.const_set(:MAX_PAGES, old)
  end

  test "does nothing for inactive shop or placeholder credential/shop_cipher" do
    travel_to Time.zone.parse("2026-02-21 12:00:00") do
      @shop.update!(last_polled_at: nil)

      @shop.update!(active: false)
      Marketplace::Tiktok::Orders::Search.stub(:call!, ->(**) { flunk "should not call API" }) do
        PollTiktokOrdersJob.perform_now(@shop.id)
      end
      assert_nil @shop.reload.last_polled_at

      @shop.update!(active: true, tiktok_credential_id: nil)
      Marketplace::Tiktok::Orders::Search.stub(:call!, ->(**) { flunk "should not call API" }) do
        PollTiktokOrdersJob.perform_now(@shop.id)
      end
      assert_nil @shop.reload.last_polled_at

      @shop.update!(tiktok_credential_id: @cred.id, shop_cipher: "")
      Marketplace::Tiktok::Orders::Search.stub(:call!, ->(**) { flunk "should not call API" }) do
        PollTiktokOrdersJob.perform_now(@shop.id)
      end
      assert_nil @shop.reload.last_polled_at
    end
  end
end
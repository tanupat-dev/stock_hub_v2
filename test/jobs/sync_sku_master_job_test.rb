# frozen_string_literal: true

require "test_helper"

class SyncSkuMasterJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @shop = Shop.create!(channel: "tiktok", shop_code: "tiktok_1", name: "TikTok 1", active: true)
  end

  test "calls service with items nil (load from marketplace_items), match_by :code" do
    called = false

    Catalog::SyncSkuMasterFromCatalog.stub(:call!, ->(shop:, items:, match_by:, enqueue_sync_stock:, dry_run:) {
      called = true
      assert_equal @shop.id, shop.id
      assert_nil items
      assert_equal :code, match_by
      assert_equal false, enqueue_sync_stock
      assert_equal false, dry_run
      { ok: true }
    }) do
      SyncSkuMasterJob.perform_now(@shop.id, enqueue_sync_stock: false, dry_run: false)
    end

    assert_equal true, called
  end

  test "does nothing when shop is inactive" do
    @shop.update_columns(active: false)

    called = false
    Catalog::SyncSkuMasterFromCatalog.stub(:call!, ->(**_) { called = true }) do
      SyncSkuMasterJob.perform_now(@shop.id)
    end

    assert_equal false, called
  end

  test "passes enqueue_sync_stock and dry_run through" do
    called = false

    Catalog::SyncSkuMasterFromCatalog.stub(:call!, ->(shop:, items:, match_by:, enqueue_sync_stock:, dry_run:) {
      called = true
      assert_equal true, enqueue_sync_stock
      assert_equal true, dry_run
      { ok: true }
    }) do
      SyncSkuMasterJob.perform_now(@shop.id, enqueue_sync_stock: true, dry_run: true)
    end

    assert_equal true, called
  end

  test "RecordNotFound: perform_now returns exception object (discard_on swallows)" do
    result = SyncSkuMasterJob.perform_now(-999, enqueue_sync_stock: false, dry_run: false)

    assert_kind_of ActiveRecord::RecordNotFound, result
    assert_match(/Couldn't find Shop/, result.message)
  end
end
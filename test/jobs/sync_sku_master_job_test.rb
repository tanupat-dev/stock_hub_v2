# frozen_string_literal: true

require "test_helper"

class SyncSkuMasterJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @shop = Shop.create!(channel: "tiktok", shop_code: "tiktok_1", name: "TikTok 1", active: true)
  end

  test "does nothing when shop is inactive" do
    @shop.update_columns(active: false)

    called = false
    Catalog::SyncSkuMasterFromCatalog.stub(:call!, ->(**_) { called = true }) do
      SyncSkuMasterJob.perform_now(@shop.id)
    end

    assert_equal false, called
  end

  test "RecordNotFound: perform_now returns exception object (discard_on swallows)" do
    result = SyncSkuMasterJob.perform_now(-999, enqueue_sync_stock: false, dry_run: false)

    assert_kind_of ActiveRecord::RecordNotFound, result
    assert_match(/Couldn't find Shop/, result.message)
  end
end

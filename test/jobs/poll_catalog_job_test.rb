# frozen_string_literal: true

require "test_helper"

class PollCatalogJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    # Ensure SyncSkuMasterJob exists for enqueue assertion
    unless Object.const_defined?(:SyncSkuMasterJob)
      Object.const_set(
        :SyncSkuMasterJob,
        Class.new(ApplicationJob) do
          queue_as :default
          def perform(*); end
        end
      )
    end

    # Ensure Marketplace::Lazada::Catalog::List exists WITHOUT referencing missing constant paths
    Marketplace.const_set(:Lazada, Module.new) unless Marketplace.const_defined?(:Lazada, false)
    lazada = Marketplace.const_get(:Lazada)

    lazada.const_set(:Catalog, Module.new) unless lazada.const_defined?(:Catalog, false)
    lazada_catalog = lazada.const_get(:Catalog)

    lazada_catalog.const_set(:List, Class.new) unless lazada_catalog.const_defined?(:List, false)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "does nothing when shop is inactive" do
    shop = Shop.create!(channel: "tiktok", shop_code: "tt_inactive", active: false)

    PollCatalogJob.perform_now(shop.id)

    assert_equal 0, enqueued_jobs.size
  end

  test "does nothing for unsupported channel" do
    shop = Shop.create!(channel: "pos", shop_code: "pos_1", active: true)

    PollCatalogJob.perform_now(shop.id)

    assert_equal 0, enqueued_jobs.size
  end

end

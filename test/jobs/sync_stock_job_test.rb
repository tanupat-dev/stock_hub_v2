# frozen_string_literal: true

require "test_helper"

class SyncStockJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "calls StockSync::PushSku and returns available" do
    sku = Sku.create!(code: "SKU001", barcode: "BC001", buffer_quantity: 3, active: true)

    StockSync::PushSku.stub(:call!, 12) do
      result = SyncStockJob.perform_now(sku.id, reason: "test", force: false)
      assert_equal 12, result
    end
  end

  test "discard_on RecordNotFound: does not raise and returns nil" do
    # discard_on should swallow RecordNotFound in this app's adapter/runtime
    result = SyncStockJob.perform_now(-999, reason: "test", force: false)
    assert_nil result
  end
end
# frozen_string_literal: true

class CleanupStockSyncRequestsJob < ApplicationJob
  queue_as :default

  DEFAULT_DELETE_PROCESSED_OLDER_THAN = 7.days
  DEFAULT_DELETE_FAILED_OLDER_THAN = 14.days
  DEFAULT_STALE_PROCESSING_OLDER_THAN = 30.minutes

  def perform(
    delete_processed_older_than: DEFAULT_DELETE_PROCESSED_OLDER_THAN,
    delete_failed_older_than: DEFAULT_DELETE_FAILED_OLDER_THAN,
    stale_processing_older_than: DEFAULT_STALE_PROCESSING_OLDER_THAN
  )
    now = Time.current

    reset_processing_count =
      StockSyncRequest
        .where(status: "processing")
        .where("updated_at < ?", now - stale_processing_older_than)
        .update_all(
          status: "failed",
          last_error: "stale_processing_timeout",
          updated_at: now
        )

    delete_completed_count =
      StockSyncRequest
        .where(status: "completed")
        .where("last_processed_at IS NOT NULL")
        .where("last_processed_at < ?", now - delete_processed_older_than)
        .delete_all

    delete_failed_count =
      StockSyncRequest
        .where(status: "failed")
        .where("updated_at < ?", now - delete_failed_older_than)
        .delete_all

    Rails.logger.info(
      {
        event: "cleanup_stock_sync_requests_job.done",
        reset_processing_count: reset_processing_count,
        delete_completed_count: delete_completed_count,
        delete_failed_count: delete_failed_count
      }.to_json
    )

    {
      ok: true,
      reset_processing_count: reset_processing_count,
      delete_completed_count: delete_completed_count,
      delete_failed_count: delete_failed_count
    }
  rescue => e
    Rails.logger.error(
      {
        event: "cleanup_stock_sync_requests_job.fail",
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
    raise
  end
end

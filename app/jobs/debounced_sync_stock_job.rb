# frozen_string_literal: true

class DebouncedSyncStockJob < ApplicationJob
  queue_as :sync_stock

  retry_on Marketplace::Tiktok::Errors::RateLimitedError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Tiktok::Errors::TransientError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Lazada::Errors::RateLimitedError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Marketplace::Lazada::Errors::TransientError,
           wait: ->(executions) { [ executions * 5, 60 ].min.seconds },
           attempts: 10

  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           wait: ->(executions) { [ executions * 3, 30 ].min.seconds },
           attempts: 8

  discard_on ActiveRecord::RecordNotFound

  def perform(sku_id)
    @sku_id = sku_id

    sku = Sku.find(sku_id)
    req = StockSyncRequest.find_by!(sku_id: sku.id)

    now = Time.current

    if req.scheduled_for > now
      self.class.set(wait_until: req.scheduled_for).perform_later(sku.id)
      req.update_column(:last_enqueued_at, now)

      Rails.logger.info(
        {
          event: "debounced_sync_stock_job.rescheduled",
          sku_id: sku.id,
          sku: sku.code,
          scheduled_for: req.scheduled_for
        }.to_json
      )

      return :rescheduled
    end

    req.with_lock do
      req.reload

      if req.scheduled_for > Time.current
        self.class.set(wait_until: req.scheduled_for).perform_later(sku.id)
        req.update_column(:last_enqueued_at, Time.current)

        Rails.logger.info(
          {
            event: "debounced_sync_stock_job.rescheduled_after_lock",
            sku_id: sku.id,
            sku: sku.code,
            scheduled_for: req.scheduled_for
          }.to_json
        )

        return :rescheduled
      end

      req.update!(
        status: "processing",
        last_error: nil
      )
    end

    Rails.logger.info(
      {
        event: "debounced_sync_stock_job.start",
        sku_id: sku.id,
        sku: sku.code,
        reason: req.last_reason
      }.to_json
    )

    available = StockSync::PushSku.call!(
      sku: sku,
      reason: req.last_reason,
      force: false
    )

    req.update!(
      status: "completed",
      last_processed_at: Time.current,
      last_enqueued_at: Time.current,
      last_error: nil
    )

    enqueue_active_cleanup

    Rails.logger.info(
      {
        event: "debounced_sync_stock_job.done",
        sku_id: sku.id,
        sku: sku.code,
        reason: req.last_reason,
        available: available
      }.to_json
    )

    available
  rescue => e
    begin
      req&.update!(
        status: "failed",
        last_error: "#{e.class}: #{e.message}"
      )
    rescue
      nil
    end

    Rails.logger.error(
      {
        event: "debounced_sync_stock_job.fail",
        sku_id: sku_id,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )

    raise
  end

  private

  def enqueue_active_cleanup
    result = CleanupStaleJobsJob.enqueue_once!(reason: "debounced_sync_stock_job")

    Rails.logger.info(
      {
        event: "debounced_sync_stock_job.cleanup_enqueue",
        sku_id: @sku_id,
        enqueue_result: result
      }.to_json
    )
  rescue => e
    Rails.logger.warn(
      {
        event: "debounced_sync_stock_job.cleanup_enqueue_fail",
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
  end
end

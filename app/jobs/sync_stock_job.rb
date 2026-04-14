# frozen_string_literal: true

class SyncStockJob < ApplicationJob
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

  def perform(sku_id, reason: nil, force: false)
    sku = Sku.find(sku_id)

    Rails.logger.info(
      {
        event: "sync_stock_job.start",
        sku_id: sku.id,
        sku: sku.code,
        reason: reason,
        forced: force
      }.to_json
    )

    available = StockSync::PushSku.call!(
      sku: sku,
      reason: reason,
      force: force
    )

    Rails.logger.info(
      {
        event: "sync_stock_job.done",
        sku_id: sku.id,
        sku: sku.code,
        reason: reason,
        forced: force,
        available: available
      }.to_json
    )

    available
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn(
      {
        event: "sync_stock_job.skip",
        sku_id: sku_id,
        reason: reason,
        forced: force,
        skip_reason: "sku_not_found",
        err_message: e.message
      }.to_json
    )
    nil
  rescue => e
    Rails.logger.error(
      {
        event: "sync_stock_job.fail",
        sku_id: sku_id,
        reason: reason,
        forced: force,
        err_class: e.class.name,
        err_message: e.message
      }.to_json
    )
    raise
  end
end

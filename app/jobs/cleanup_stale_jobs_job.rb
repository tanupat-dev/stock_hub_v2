# frozen_string_literal: true

class CleanupStaleJobsJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 1.hour
  ENQUEUE_ONCE_WINDOW = 5.minutes

  TARGET_JOB_CLASSES = %w[
    DebouncedSyncStockJob
    PushInventoryJob
    RefreshMarketplaceItemJob
    InventoryReconcileJob
  ].freeze

  class << self
    def enqueue_once!(reason: nil, window: ENQUEUE_ONCE_WINDOW)
      return :skipped if recently_enqueued?(window)

      perform_later
      mark_enqueued!(window)

      Rails.logger.info(
        {
          event: "cleanup_stale_jobs_job.enqueue_once",
          result: "enqueued",
          reason: reason,
          window_seconds: window.to_i
        }.to_json
      )

      :enqueued
    rescue => e
      Rails.logger.warn(
        {
          event: "cleanup_stale_jobs_job.enqueue_once_fail",
          reason: reason,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      :failed
    end

    private

    def recently_enqueued?(window)
      ts = Rails.cache.read(cache_key)
      ts.present? && ts > window.ago
    end

    def mark_enqueued!(window)
      Rails.cache.write(
        cache_key,
        Time.current,
        expires_in: window
      )
    end

    def cache_key
      "cleanup_stale_jobs_job:enqueue_once"
    end
  end

  def perform
    cutoff = Time.current - STALE_AFTER

    stale_jobs = SolidQueue::Job
      .where(finished_at: nil, class_name: TARGET_JOB_CLASSES)
      .where("created_at < ?", cutoff)
      .order(:created_at)

    scanned = 0
    deleted = 0

    stale_jobs.find_each do |job|
      scanned += 1
      next if claimed?(job.id)

      job.delete
      deleted += 1

      Rails.logger.warn(
        {
          event: "cleanup_stale_jobs_job.deleted",
          job_id: job.id,
          class_name: job.class_name,
          queue_name: job.queue_name,
          created_at: job.created_at,
          cutoff: cutoff
        }.to_json
      )
    rescue => e
      Rails.logger.error(
        {
          event: "cleanup_stale_jobs_job.delete_fail",
          job_id: job.id,
          class_name: job.class_name,
          queue_name: job.queue_name,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
    end

    Rails.logger.info(
      {
        event: "cleanup_stale_jobs_job.done",
        cutoff: cutoff,
        scanned: scanned,
        deleted: deleted
      }.to_json
    )

    {
      ok: true,
      cutoff: cutoff,
      scanned: scanned,
      deleted: deleted
    }
  end

  private

  def claimed?(job_id)
    SolidQueue::ClaimedExecution.where(job_id: job_id).exists?
  end
end

# frozen_string_literal: true

class CleanupStaleJobsJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 1.hour
  TARGET_JOB_CLASSES = %w[
    DebouncedSyncStockJob
    PushInventoryJob
    RefreshMarketplaceItemJob
    InventoryReconcileJob
  ].freeze

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

# app/jobs/cleanup_stale_jobs_job.rb
class CleanupStaleJobsJob < ApplicationJob
  queue_as :default

  def perform
    stale = SolidQueue::Job
      .where(finished_at: nil)
      .where("created_at < ?", 1.hour.ago)

    deleted = stale.delete_all

    Rails.logger.info(
      {
        event: "cleanup_stale_jobs.done",
        deleted: deleted
      }.to_json
    )
  end
end

# frozen_string_literal: true

class SkuImportBatch < ApplicationRecord
  has_one_attached :file

  STATUSES = %w[pending processing completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  def processing!
    update!(status: "processing", started_at: Time.current)
  end

  def completed!
    update!(status: "completed", completed_at: Time.current)
  end

  def failed!(error)
    update!(
      status: "failed",
      error_message: error.to_s,
      completed_at: Time.current
    )
  end
end

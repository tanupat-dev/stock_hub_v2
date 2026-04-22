# frozen_string_literal: true

class StockSyncRequest < ApplicationRecord
  belongs_to :sku

  STATUSES = %w[pending processing completed failed].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :first_requested_at, :last_requested_at, :scheduled_for, presence: true
end

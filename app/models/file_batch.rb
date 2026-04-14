# frozen_string_literal: true

class FileBatch < ApplicationRecord
  belongs_to :shop

  KINDS = %w[
    shopee_order_import
    shopee_stock_export
    shopee_return_import
  ].freeze

  STATUSES = %w[
    pending
    processing
    completed
    failed
    completed_with_errors
  ].freeze

  validates :channel, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
end

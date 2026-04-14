# frozen_string_literal: true

class StockCountLine < ApplicationRecord
  STATUSES = %w[pending confirmed].freeze

  belongs_to :stock_count_session
  belongs_to :sku

  validates :sku_code_snapshot, presence: true
  validates :system_qty_snapshot, numericality: { greater_than_or_equal_to: 0 }
  validates :counted_qty, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  def pending?
    status == "pending"
  end

  def confirmed?
    status == "confirmed"
  end
end

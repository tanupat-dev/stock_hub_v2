# frozen_string_literal: true

class StockCountSession < ApplicationRecord
  STATUSES = %w[open confirmed cancelled].freeze

  belongs_to :shop
  has_many :stock_count_lines, dependent: :destroy

  validates :session_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  scope :open_sessions, -> { where(status: "open") }

  def open?
    status == "open"
  end

  def confirmed?
    status == "confirmed"
  end

  def cancelled?
    status == "cancelled"
  end
end

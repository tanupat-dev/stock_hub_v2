# frozen_string_literal: true

class PosReturn < ApplicationRecord
  STATUSES = %w[open completed cancelled].freeze

  belongs_to :shop
  belongs_to :pos_sale
  has_many :pos_return_lines, dependent: :destroy

  validates :return_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  def open?
    status == "open"
  end

  def completed?
    status == "completed"
  end

  def cancelled?
    status == "cancelled"
  end
end

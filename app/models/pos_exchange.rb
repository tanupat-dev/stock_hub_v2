# frozen_string_literal: true

class PosExchange < ApplicationRecord
  STATUSES = %w[open completed cancelled].freeze

  belongs_to :shop
  belongs_to :pos_sale
  belongs_to :pos_return, optional: true
  belongs_to :new_pos_sale, class_name: "PosSale", optional: true

  validates :exchange_number, presence: true, uniqueness: true
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

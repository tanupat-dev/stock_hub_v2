# frozen_string_literal: true

class PosSaleLine < ApplicationRecord
  STATUSES = %w[
    active
    voided
  ].freeze

  belongs_to :pos_sale
  belongs_to :sku

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :sku_code_snapshot, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :quantity, numericality: { greater_than: 0 }

  scope :active_lines, -> { where(status: "active") }
  scope :voided_lines, -> { where(status: "voided") }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def active?
    status == "active"
  end

  def voided?
    status == "voided"
  end

  has_many :pos_return_lines, dependent: :restrict_with_exception

  def returned_qty
    if association(:pos_return_lines).loaded?
      pos_return_lines.sum { |line| line.quantity.to_i }
    else
      pos_return_lines.sum(:quantity)
    end
  end

  def returnable_qty
    remaining = quantity.to_i - returned_qty
    remaining.positive? ? remaining : 0
  end
end

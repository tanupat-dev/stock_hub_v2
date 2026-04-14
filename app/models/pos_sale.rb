# frozen_string_literal: true

class PosSale < ApplicationRecord
  STATUSES = %w[
    cart
    checked_out
    voided
  ].freeze

  belongs_to :shop
  has_many :pos_sale_lines, dependent: :destroy
  has_many :pos_returns, dependent: :restrict_with_exception
  has_many :origin_exchanges, class_name: "PosExchange", dependent: :restrict_with_exception
  has_many :replacement_exchanges, class_name: "PosExchange", foreign_key: :new_pos_sale_id, dependent: :nullify


  validates :sale_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :item_count, numericality: { greater_than_or_equal_to: 0 }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :carts, -> { where(status: "cart") }
  scope :checked_out, -> { where(status: "checked_out") }
  scope :voided, -> { where(status: "voided") }

  def cart?
    status == "cart"
  end

  def checked_out?
    status == "checked_out"
  end

  def voided?
    status == "voided"
  end

  def recalculate_item_count!
    total = pos_sale_lines.where(status: "active").sum(:quantity)
    update!(item_count: total)
  end
end

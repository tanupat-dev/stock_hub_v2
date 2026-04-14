# frozen_string_literal: true

class OrderLine < ApplicationRecord
  belongs_to :order
  belongs_to :sku, optional: true
  has_many :return_scans, dependent: :destroy

  validates :idempotency_key, presence: true, uniqueness: true
  validates :quantity, numericality: { greater_than: 0 }

  # ===== Return quantities (used by POS return flow) =====

  # จำนวนที่สแกนคืนแล้ว (รวมทั้งหมด)
  # ถ้า preloaded return_scans จะไม่ยิง SUM query ซ้ำ
  def returned_qty
    if association(:return_scans).loaded?
      return_scans.sum { |rs| rs.quantity.to_i }
    else
      return_scans.sum(:quantity)
    end
  end

  # จำนวนที่ยังสแกนคืนได้ (กันคืนเกินที่ขาย)
  def return_pending_qty
    pending = quantity.to_i - returned_qty
    pending.positive? ? pending : 0
  end

  def fully_returned?
    return_pending_qty.zero?
  end
end
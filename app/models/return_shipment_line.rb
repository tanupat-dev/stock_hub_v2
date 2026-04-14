# frozen_string_literal: true

class ReturnShipmentLine < ApplicationRecord
  belongs_to :return_shipment
  belongs_to :order_line, optional: true
  belongs_to :sku, optional: true

  validates :sku_code_snapshot, presence: true
  validates :qty_returned, numericality: { greater_than: 0 }

  def scanned_qty
    scans = return_shipment.return_scans

    if order_line_id.present?
      scans.where(order_line_id: order_line_id).sum(:quantity)
    elsif sku_id.present?
      scans.where(sku_id: sku_id).sum(:quantity)
    else
      0
    end
  end

  def pending_scan_qty
    pending = qty_returned.to_i - scanned_qty.to_i
    pending.positive? ? pending : 0
  end

  def fully_scanned?
    pending_scan_qty.zero?
  end
end

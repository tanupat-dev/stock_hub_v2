# frozen_string_literal: true

class ReturnShipment < ApplicationRecord
  STATUS_STORE_VALUES = %w[
    pending_scan
    partial_scanned
    received_scanned
  ].freeze

  belongs_to :shop
  belongs_to :order, optional: true

  has_many :return_scans, dependent: :destroy
  has_many :return_shipment_lines, dependent: :destroy

  validates :channel, :shop_id, :external_order_id, presence: true
  validates :status_store, presence: true, inclusion: { in: STATUS_STORE_VALUES }

  def pending_scan?
    status_store == "pending_scan"
  end

  def partial_scanned?
    status_store == "partial_scanned"
  end

  def received_scanned?
    status_store == "received_scanned"
  end

  def scanned_any?
    return_scans.exists?
  end

  def total_qty_requested
    return_shipment_lines.sum(:qty_returned)
  end

  def total_qty_scanned
    return_scans.sum(:quantity)
  end

  def fully_scanned?
    lines = return_shipment_lines.to_a
    return false if lines.empty?

    lines.all?(&:fully_scanned?)
  end

  def derived_status_store
    return "received_scanned" if fully_scanned?
    return "partial_scanned" if scanned_any?

    "pending_scan"
  end

  def refresh_status_store!
    next_status = derived_status_store
    return status_store if status_store == next_status

    update!(status_store: next_status)
    next_status
  end
end

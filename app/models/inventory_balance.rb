# frozen_string_literal: true

class InventoryBalance < ApplicationRecord
  belongs_to :sku, optional: true
  belongs_to :stock_identity, optional: true

  validates :on_hand, numericality: { greater_than_or_equal_to: 0 }
  validates :reserved, numericality: { greater_than_or_equal_to: 0 }

  after_commit :enqueue_stock_sync_if_relevant, on: %i[create update]

  def frozen_now?
    frozen_at.present?
  end

  def raw_available
    on_hand - reserved
  end

  def store_available
    [ raw_available, 0 ].max
  end

  def online_available_raw(buffer_quantity:)
    raw_available - buffer_quantity.to_i
  end

  def online_available(buffer_quantity:)
    [ online_available_raw(buffer_quantity: buffer_quantity), 0 ].max
  end

  private

  def enqueue_stock_sync_if_relevant
    return if ENV["DISABLE_JOBS"] == "1"
    return unless solid_queue_ready?
    return unless stock_sync_relevant_change?

    root_sku = stock_sync_root_sku
    return if root_sku.nil?
    return unless StockSync::Rollout.sku_allowed?(root_sku.code)

    StockSync::RequestDebouncer.call!(
      sku: root_sku,
      reason: "inventory_balance_change"
    )
  end

  def stock_sync_relevant_change?
    previous_changes.key?("on_hand") ||
      previous_changes.key?("reserved") ||
      previous_changes.key?("frozen_at") ||
      previous_changes.key?("freeze_reason")
  end

  def stock_sync_root_sku
    if stock_identity_id.present?
      Sku.where(stock_identity_id: stock_identity_id).order(:id).first
    elsif sku_id.present?
      Sku.find_by(id: sku_id)
    end
  end

  def solid_queue_ready?
    SolidQueue::Job.table_exists?
  rescue StandardError
    false
  end
end

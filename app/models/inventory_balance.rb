# frozen_string_literal: true

class InventoryBalance < ApplicationRecord
  belongs_to :sku

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

    return unless previous_changes.key?("on_hand") ||
      previous_changes.key?("reserved") ||
      previous_changes.key?("frozen_at") ||
      previous_changes.key?("freeze_reason")

    sku = self.sku
    return if sku.nil?

    return unless StockSync::Rollout.sku_allowed?(sku.code)

    StockSync::RequestDebouncer.call!(
      sku: sku,
      reason: "inventory_balance_change"
    )
  end

  def solid_queue_ready?
    SolidQueue::Job.table_exists?
  rescue StandardError
    false
  end
end

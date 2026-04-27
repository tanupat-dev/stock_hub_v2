# frozen_string_literal: true

class Sku < ApplicationRecord
  belongs_to :stock_identity, optional: true

  has_one :inventory_balance,
          class_name: "InventoryBalance"

  has_many :order_lines
  has_many :sku_mappings
  has_many :stock_movements
  has_many :stock_sync_requests, dependent: :destroy
  has_many :pos_sale_lines, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true
  validates :barcode, uniqueness: true, allow_nil: true
  validates :buffer_quantity, numericality: { greater_than_or_equal_to: 0 }

  after_commit :sync_stock_if_buffer_changed, on: :update

  def inventory_balance
    if stock_identity_id.present?
      InventoryBalance.find_by(stock_identity_id: stock_identity_id) || super
    else
      super
    end
  end

  def store_available
    b = inventory_balance
    return 0 unless b

    b.store_available
  end

  def online_available
    b = inventory_balance
    return 0 unless b
    return 0 if b.frozen_now?

    b.online_available(buffer_quantity: buffer_quantity)
  end

  def sellable
    online_available
  end

  private

  def sync_stock_if_buffer_changed
    return unless previous_changes.key?("buffer_quantity")

    unfreeze_result = Inventory::UnfreezeIfResolved.call!(sku: self, trigger: "buffer_changed")

    return if unfreeze_result == :unfrozen

    StockSync::RequestDebouncer.call!(
      sku: self,
      reason: "buffer_changed"
    )
  end
end

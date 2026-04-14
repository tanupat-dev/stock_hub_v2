# frozen_string_literal: true

class InventoryAction < ApplicationRecord
  belongs_to :sku
  belongs_to :order_line, optional: true

  ACTION_TYPES = %w[
    reserve
    release
    commit
    return_scan
    stock_in
    stock_adjust
  ].freeze

  validates :action_type, presence: true, inclusion: { in: ACTION_TYPES }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :quantity, numericality: { greater_than: 0 }
end
# frozen_string_literal: true

class PosReturnLine < ApplicationRecord
  belongs_to :pos_return
  belongs_to :pos_sale_line
  belongs_to :sku

  validates :quantity, numericality: { greater_than: 0 }
  validates :sku_code_snapshot, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
end

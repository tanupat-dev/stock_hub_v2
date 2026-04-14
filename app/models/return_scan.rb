# frozen_string_literal: true

class ReturnScan < ApplicationRecord
  belongs_to :return_shipment
  belongs_to :order_line
  belongs_to :sku

  validates :quantity, numericality: { greater_than: 0 }
  validates :idempotency_key, presence: true, uniqueness: true
end

# frozen_string_literal: true

class OversellAllocation < ApplicationRecord
  belongs_to :oversell_incident
  belongs_to :order_line
  belongs_to :sku

  validates :quantity, numericality: { greater_than: 0 }
end
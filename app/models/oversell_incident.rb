# frozen_string_literal: true

class OversellIncident < ApplicationRecord
  belongs_to :sku
  has_many :oversell_allocations, dependent: :destroy

  validates :shortfall_qty, numericality: { greater_than: 0 }
  validates :trigger, :status, :idempotency_key, presence: true
  validates :status, inclusion: { in: %w[open resolved ignored] }
  validates :idempotency_key, uniqueness: true
end
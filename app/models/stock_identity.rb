# frozen_string_literal: true

class StockIdentity < ApplicationRecord
  has_many :skus

  has_one :inventory_balance,
          class_name: "InventoryBalance",
          foreign_key: :stock_identity_id

  validates :code, uniqueness: true, allow_nil: true
end

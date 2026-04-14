# frozen_string_literal: true

class ShopSkuSyncState < ApplicationRecord
  belongs_to :shop
  belongs_to :sku

  validates :fail_count, numericality: { greater_than_or_equal_to: 0 }
end
# app/models/marketplace_item.rb
class MarketplaceItem < ApplicationRecord
  belongs_to :shop

  scope :with_sku, -> { where.not(external_sku: [nil, ""]) }
end
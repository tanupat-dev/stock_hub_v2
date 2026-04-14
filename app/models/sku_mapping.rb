class SkuMapping < ApplicationRecord
  belongs_to :shop
  belongs_to :sku

  validates :channel, presence: true
  validates :external_sku, presence: true, uniqueness: { scope: %i[channel shop_id] }
end
class StockMovement < ApplicationRecord
  belongs_to :sku

  validates :delta_on_hand, presence: true
  validates :reason, presence: true
end
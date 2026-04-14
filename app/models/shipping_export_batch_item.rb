# frozen_string_literal: true

class ShippingExportBatchItem < ApplicationRecord
  belongs_to :shipping_export_batch
  belongs_to :order

  validates :channel, presence: true
  validates :shop_id, presence: true
  validates :external_order_id, presence: true
end

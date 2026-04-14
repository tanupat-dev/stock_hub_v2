# frozen_string_literal: true

class ShippingExportBatch < ApplicationRecord
  STATUSES = %w[building completed failed].freeze

  has_many :shipping_export_batch_items, dependent: :destroy

  validates :export_key, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :template_name, presence: true
  validates :requested_at, presence: true
end

# frozen_string_literal: true

class Shop < ApplicationRecord
  CHANNELS = %w[tiktok lazada shopee pos].freeze

  belongs_to :tiktok_app, optional: true
  belongs_to :tiktok_credential, optional: true
  belongs_to :lazada_credential, optional: true
  belongs_to :lazada_app, optional: true

  has_many :orders, dependent: :destroy
  has_many :sku_mappings, dependent: :destroy
  has_many :shop_sku_sync_states, dependent: :destroy
  has_many :pos_sales, dependent: :destroy
  has_many :pos_returns, dependent: :destroy
  has_many :pos_exchanges, dependent: :destroy
  has_many :return_shipments, dependent: :destroy
  has_many :file_batches, dependent: :destroy

  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :shop_code, presence: true, uniqueness: { scope: :channel }

  scope :active, -> { where(active: true) }
  scope :stock_sync_enabled, -> { where(stock_sync_enabled: true) }
  scope :tiktok_real, -> { where(channel: "tiktok").where.not(tiktok_credential_id: nil) }
  scope :tiktok_placeholders, -> { where(channel: "tiktok", tiktok_credential_id: nil) }
end

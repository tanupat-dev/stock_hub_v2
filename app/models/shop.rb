# app/models/shop.rb
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

  class << self
    def normalize_filter_codes(value)
      raw = value.to_s.strip
      return [] if raw.blank?

      case raw
      when "TikTok 1"
        where(channel: "tiktok").select { |shop| display_label_for(shop) == "TikTok 1" }.map(&:shop_code)
      when "TikTok 2"
        where(channel: "tiktok").select { |shop| display_label_for(shop) == "TikTok 2" }.map(&:shop_code)
      when "Lazada 1"
        where(channel: "lazada").select { |shop| display_label_for(shop) == "Lazada 1" }.map(&:shop_code)
      when "Lazada 2"
        where(channel: "lazada").select { |shop| display_label_for(shop) == "Lazada 2" }.map(&:shop_code)
      when "Shopee"
        where(channel: "shopee").pluck(:shop_code)
      when "POS"
        where(channel: "pos").pluck(:shop_code)
      else
        [ raw ]
      end
    end

    def display_label_for(shop)
      return "-" if shop.nil?

      code = shop.shop_code.to_s.strip
      code_downcase = code.downcase
      name = shop.name.to_s.strip

      # TikTok
      return "TikTok 1" if code == "THLCJ4W23M"
      return "TikTok 2" if code == "THLCM7WX8H"
      return "TikTok 1" if code_downcase == "tiktok_1"
      return "TikTok 2" if code_downcase == "tiktok_2"
      return "TikTok 1" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 1").zero?
      return "TikTok 2" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 2").zero?
      return "TikTok 1" if name.casecmp("Thailumlongshop II").zero?
      return "TikTok 2" if name.casecmp("Young smile shoes").zero?

      # Lazada
      return "Lazada 1" if code == "THJ2HAHL"
      return "Lazada 2" if code == "TH1JHM87NL"
      return "Lazada 1" if code_downcase == "lazada_1"
      return "Lazada 2" if code_downcase == "lazada_2"
      return "Lazada 1" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 1").zero?
      return "Lazada 2" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 2").zero?
      return "Lazada 1" if name.casecmp("Thai Lumlong Shop").zero?
      return "Lazada 2" if name.casecmp("Thai Lumlong Shop II").zero?
      return "Lazada 1" if name.casecmp("Lazada 1").zero?
      return "Lazada 2" if name.casecmp("Lazada 2").zero?

      # Shopee / POS
      return "Shopee" if code_downcase.start_with?("shopee")
      return "Shopee" if name.downcase.start_with?("shopee")
      return "POS" if code_downcase == "pos" || code_downcase.start_with?("pos")

      name.presence || code
    end
  end
end

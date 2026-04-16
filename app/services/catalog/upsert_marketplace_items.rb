# app/services/catalog/upsert_marketplace_items.rb
# frozen_string_literal: true

module Catalog
  class UpsertMarketplaceItems
    BATCH_SIZE = 50

    def self.call!(shop:, items:)
      new(shop, items).call!
    end

    def initialize(shop, items)
      @shop = shop
      @items = items || []
      raise ArgumentError, "shop is required" if @shop.nil?
    end

    def call!
      return 0 if @items.blank?

      now = Time.current

      rows = @items.map do |i|
        ext_sku = i[:external_sku].to_s.strip
        ext_sku = nil if ext_sku.blank?

        ext_product_id = i[:external_product_id].to_s.strip
        ext_product_id = nil if ext_product_id.blank?

        ext_variant_id = i[:external_variant_id].to_s.strip
        ext_variant_id = nil if ext_variant_id.blank?

        {
          shop_id: @shop.id,
          channel: @shop.channel,
          external_product_id: ext_product_id,
          external_variant_id: ext_variant_id,
          external_sku: ext_sku,
          title: i[:title].to_s.presence,
          status: i[:status].to_s.strip.upcase.presence,
          available_stock: i[:available_stock].to_i,
          raw_payload: i[:raw_payload].is_a?(Hash) ? i[:raw_payload] : (i[:raw_payload] || {}),
          synced_at: now,
          created_at: now,
          updated_at: now
        }
      end

      total = 0

      rows.each_slice(BATCH_SIZE) do |chunk|
        MarketplaceItem.upsert_all(
          chunk,
          unique_by: :uniq_marketplace_variant,
          record_timestamps: false,
          update_only: %i[
            external_product_id external_sku title status
            available_stock raw_payload synced_at updated_at
          ]
        )

        total += chunk.size
      end

      total
    end
  end
end

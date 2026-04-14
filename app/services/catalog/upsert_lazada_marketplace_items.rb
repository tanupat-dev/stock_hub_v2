# frozen_string_literal: true

module Catalog
  class UpsertLazadaMarketplaceItems
    def self.call!(shop:, products:)
      new(shop, products).call!
    end

    def initialize(shop, products)
      @shop = shop
      @products = Array(products)
      @now = Time.current
      @upserted = 0
      @skipped = 0
    end

    def call!
      @products.each do |product|
        upsert_product!(product)
      end

      {
        ok: true,
        shop_id: @shop.id,
        channel: @shop.channel,
        products: @products.size,
        upserted: @upserted,
        skipped: @skipped
      }
    end

    private

    def upsert_product!(product)
      item_id = product["item_id"].to_s.strip
      title = product.dig("attributes", "name").to_s.strip
      product_status = normalize_status(product["status"])

      Array(product["skus"]).each do |sku|
        external_variant_id = sku["SkuId"].to_s.strip
        external_sku = sku["SellerSku"].to_s.strip

        if external_variant_id.blank? && external_sku.blank?
          @skipped += 1
          next
        end

        row_status = normalize_status(sku["Status"]).presence || product_status
        available_stock = extract_available_stock(sku)

        record =
          if external_variant_id.present?
            MarketplaceItem.find_or_initialize_by(
              shop_id: @shop.id,
              external_variant_id: external_variant_id
            )
          else
            MarketplaceItem.find_or_initialize_by(
              shop_id: @shop.id,
              external_sku: external_sku
            )
          end

        record.channel = @shop.channel
        record.external_product_id = item_id.presence
        record.external_variant_id = external_variant_id.presence
        record.external_sku = external_sku.presence
        record.title = title.presence
        record.status = row_status
        record.available_stock = available_stock
        record.raw_payload = {
          "product" => product,
          "sku" => sku
        }
        record.synced_at = @now

        record.save!
        @upserted += 1
      end
    end

    def extract_available_stock(sku)
      v = sku["Available"]
      v = sku["quantity"] if v.nil?
      v.to_i
    end

    def normalize_status(value)
      s = value.to_s.strip
      return nil if s.blank?

      normalized = s.downcase.gsub(/[^\p{Alnum}]+/, "_").gsub(/\A_+|_+\z/, "")

      case normalized
      when "active", "live", "activate"
        "ACTIVATE"
      when "inactive", "in_active"
        "INACTIVE"
      when "pending", "pending_qc", "pending_qc_seller_activated"
        "PENDING"
      when "rejected", "reject"
        "REJECTED"
      when "deleted"
        "DELETED"
      when "sold_out", "soldout"
        "SOLD_OUT"
      when "suspended"
        "SUSPENDED"
      else
        normalized.upcase
      end
    end
  end
end

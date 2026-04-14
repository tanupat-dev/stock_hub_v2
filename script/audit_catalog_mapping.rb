# frozen_string_literal: true

# Usage:
# CHANNEL=tiktok bin/rails runner script/audit_catalog_mapping.rb
# CHANNEL=lazada bin/rails runner script/audit_catalog_mapping.rb

class CatalogMappingAudit
  def self.run!
    new.run!
  end

  def initialize
    @channel = ENV["CHANNEL"].to_s.presence
    @shop_id = ENV["SHOP_ID"]&.to_i
  end

  def run!
    run_tiktok! if @channel.blank? || @channel == "tiktok"
    run_lazada! if @channel.blank? || @channel == "lazada"
  end

  # =========================
  # TIKTOK
  # =========================

  def run_tiktok!
    shops = Shop.where(channel: "tiktok", active: true)
    shops = shops.where(id: @shop_id) if @shop_id

    shops.each do |shop|
      audit_tiktok_shop(shop)
    end
  end

  def audit_tiktok_shop(shop)
    puts({
      event: "catalog.audit.tiktok.start",
      shop_id: shop.id,
      shop_code: shop.shop_code
    }.to_json)

    result = {
      total: 0,
      has_seller_sku: 0,
      blank_seller_sku: 0,
      resolved_exact: 0,
      resolved_normalized: 0,
      unresolved: 0,
      samples: []
    }

    resp = Marketplace::Tiktok::Catalog::List.call!(
      shop: shop,
      page_size: 100,
      max_pages: 20
    )

    items = Array(resp[:items])

    items.each do |item|
      seller_sku = item[:external_sku].to_s.strip

      result[:total] += 1

      if seller_sku.blank?
        result[:blank_seller_sku] += 1

        result[:samples] << {
          type: "blank_seller_sku",
          sku_id: item[:external_variant_id],
          product: item[:name]
        } if result[:samples].size < 10

        next
      end

      result[:has_seller_sku] += 1

      exact = Sku.find_by(code: seller_sku)

      if exact
        result[:resolved_exact] += 1
        next
      end

      normalized = seller_sku.gsub(/\s+/, "")
      norm_match = Sku.find_by(code: normalized)

      if norm_match
        result[:resolved_normalized] += 1
        next
      end

      result[:unresolved] += 1

      if result[:samples].size < 20
        result[:samples] << {
          type: "unresolved",
          seller_sku: seller_sku,
          normalized: normalized
        }
      end
    end

    puts(result.merge(event: "catalog.audit.tiktok.summary").to_json)
  end

  # =========================
  # LAZADA
  # =========================

  def run_lazada!
    shops = Shop.where(channel: "lazada", active: true)
    shops = shops.where(id: @shop_id) if @shop_id

    shops.each do |shop|
      audit_lazada_shop(shop)
    end
  end

  def audit_lazada_shop(shop)
    puts({
      event: "catalog.audit.lazada.start",
      shop_id: shop.id,
      shop_code: shop.shop_code
    }.to_json)

    result = {
      total: 0,
      resolved_exact: 0,
      resolved_normalized: 0,
      unresolved: 0,
      samples: []
    }

    offset = 0

    loop do
      resp = Marketplace::Lazada::Catalog::List.call!(
        shop: shop,
        offset: offset,
        limit: 100
      )

      items = Array(resp["products"])
      break if items.empty?

      items.each do |p|
        skus = Array(p["skus"])

        skus.each do |sku|
          result[:total] += 1

          seller_sku = sku["seller_sku"].to_s.strip

          exact = Sku.find_by(code: seller_sku)

          if exact
            result[:resolved_exact] += 1
            next
          end

          normalized = normalize_lazada(seller_sku)
          norm_match = Sku.find_by(code: normalized)

          if norm_match
            result[:resolved_normalized] += 1
            next
          end

          result[:unresolved] += 1

          if result[:samples].size < 20
            result[:samples] << {
              seller_sku: seller_sku,
              normalized: normalized
            }
          end
        end
      end

      offset += items.size
      break if items.size < 100
    end

    puts(result.merge(event: "catalog.audit.lazada.summary").to_json)
  end

  def normalize_lazada(code)
    code.to_s
        .gsub(/\s+/, "")
        .gsub("EU:", "")
        .gsub("UK:", "")
        .gsub("-", ".")
        .strip
  end
end

CatalogMappingAudit.run!

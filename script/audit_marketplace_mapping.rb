# frozen_string_literal: true

# Usage examples:
#
# Read-only audit (default)
#   bin/rails runner script/audit_marketplace_mapping.rb
#
# TikTok only, last 24 hours
#   CHANNEL=tiktok LOOKBACK_HOURS=24 bin/rails runner script/audit_marketplace_mapping.rb
#
# Lazada only, last 72 hours, max 5 pages
#   CHANNEL=lazada LOOKBACK_HOURS=72 MAX_PAGES=5 bin/rails runner script/audit_marketplace_mapping.rb
#
# Write mode (actually upsert orders while auditing)
#   WRITE=true CHANNEL=tiktok LOOKBACK_HOURS=24 bin/rails runner script/audit_marketplace_mapping.rb
#
# Specific shop only
#   CHANNEL=tiktok SHOP_ID=11 LOOKBACK_HOURS=24 bin/rails runner script/audit_marketplace_mapping.rb

require "json"
require "time"

class MarketplaceMappingAudit
  DEFAULT_LOOKBACK_HOURS = 24
  DEFAULT_MAX_PAGES = 3
  DEFAULT_TIKTOK_PAGE_SIZE = 50
  DEFAULT_LAZADA_LIMIT = 100

  def self.run!
    new.run!
  end

  def initialize
    @channel = ENV["CHANNEL"].to_s.strip.presence
    @shop_id = ENV["SHOP_ID"].to_s.strip.presence&.to_i
    @lookback_hours = (ENV["LOOKBACK_HOURS"].to_i > 0 ? ENV["LOOKBACK_HOURS"].to_i : DEFAULT_LOOKBACK_HOURS)
    @max_pages = (ENV["MAX_PAGES"].to_i > 0 ? ENV["MAX_PAGES"].to_i : DEFAULT_MAX_PAGES)
    @write = ENV["WRITE"].to_s.strip.downcase == "true"
    @now = Time.current
    @from_time = @now - @lookback_hours.hours
  end

  def run!
    puts banner_payload.to_json

    run_tiktok! if @channel.blank? || @channel == "tiktok"
    run_lazada! if @channel.blank? || @channel == "lazada"

    puts({ event: "marketplace.mapping_audit.done", at: Time.current.iso8601 }.to_json)
  end

  private

  def banner_payload
    {
      event: "marketplace.mapping_audit.start",
      channel: @channel || "all",
      shop_id: @shop_id,
      lookback_hours: @lookback_hours,
      from_time: @from_time.iso8601,
      to_time: @now.iso8601,
      max_pages: @max_pages,
      write: @write
    }
  end

  # =========================
  # TikTok
  # =========================

  def run_tiktok!
    shops = Shop.where(channel: "tiktok", active: true)
    shops = shops.where(id: @shop_id) if @shop_id.present?
    shops = shops.where.not(tiktok_credential_id: nil)

    if shops.empty?
      puts({ event: "marketplace.mapping_audit.tiktok.no_shops" }.to_json)
      return
    end

    shops.find_each do |shop|
      audit_tiktok_shop!(shop)
    end
  end

  def audit_tiktok_shop!(shop)
    puts({
      event: "marketplace.mapping_audit.tiktok.shop_start",
      shop_id: shop.id,
      shop_code: shop.shop_code,
      from_time: @from_time.iso8601,
      to_time: @now.iso8601
    }.to_json)

    update_time_ge = @from_time.to_i
    update_time_lt = @now.to_i

    page_token = nil
    page = 0
    summary = empty_summary(channel: "tiktok", shop: shop)

    loop do
      break if page >= @max_pages

      resp = Orders::Tiktok::SearchOrders.call!(
        shop: shop,
        update_time_ge: update_time_ge,
        update_time_lt: update_time_lt,
        page_token: page_token,
        page_size: DEFAULT_TIKTOK_PAGE_SIZE
      )

      rows = Array(resp[:orders])
      break if rows.empty?

      page += 1
      summary[:pages] = page
      summary[:search_rows] += rows.size

      rows.each do |search_row|
        order_id = search_row["id"].to_s.presence || search_row["order_id"].to_s.presence
        next if order_id.blank?

        detail = Marketplace::Tiktok::Orders::Get.call!(shop: shop, order_id: order_id)
        summary[:detail_rows] += 1

        Array(detail["line_items"]).each do |line|
          result = resolve_tiktok_line(shop: shop, line: line)
          absorb_result!(summary, result, line: line)
        end

        if @write
          Orders::Tiktok::Upsert.call!(shop: shop, raw_order: detail)
          order = Order.find_by(channel: "tiktok", shop_id: shop.id, external_order_id: order_id)
          Orders::Tiktok::UpdateFromDetail.call!(order: order, payload: detail) if order.present?
          summary[:writes] += 1
        end
      end

      page_token = resp[:next_page_token].presence
      break if page_token.blank?
    end

    puts(summary.to_json)
  rescue => e
    puts({
      event: "marketplace.mapping_audit.tiktok.shop_fail",
      shop_id: shop.id,
      shop_code: shop.shop_code,
      err_class: e.class.name,
      err_message: e.message
    }.to_json)
  end

  def resolve_tiktok_line(shop:, line:)
    seller_sku_raw = line["seller_sku"].to_s
    seller_sku = seller_sku_raw.strip
    external_platform_sku_id = line["sku_id"].to_s.strip

    return {
      state: "blank_seller_sku_with_platform_sku_id",
      seller_sku_raw: seller_sku_raw,
      seller_sku: nil,
      platform_sku_id: external_platform_sku_id
    } if seller_sku.blank? && external_platform_sku_id.present?

    return {
      state: "blank_seller_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: nil,
      platform_sku_id: external_platform_sku_id
    } if seller_sku.blank?

    return {
      state: "numeric_seller_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      platform_sku_id: external_platform_sku_id
    } if seller_sku.match?(/\A\d+\z/)

    mapping = SkuMapping.includes(:sku).find_by(
      channel: "tiktok",
      shop_id: shop.id,
      external_sku: seller_sku
    )

    return {
      state: "resolved_by_mapping",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      platform_sku_id: external_platform_sku_id,
      sku_id: mapping.sku_id,
      sku_code: mapping.sku&.code
    } if mapping.present?

    exact = Sku.find_by(code: seller_sku)
    return {
      state: "resolved_by_exact_code",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      platform_sku_id: external_platform_sku_id,
      sku_id: exact.id,
      sku_code: exact.code
    } if exact.present?

    normalized = normalize_code(seller_sku_raw)
    normalized_match = normalized.present? ? Sku.find_by(code: normalized) : nil
    return {
      state: "resolved_by_normalized_code",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      normalized_sku: normalized,
      platform_sku_id: external_platform_sku_id,
      sku_id: normalized_match.id,
      sku_code: normalized_match.code
    } if normalized_match.present?

    {
      state: "unresolved_text_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      normalized_sku: normalized,
      platform_sku_id: external_platform_sku_id
    }
  end

  # =========================
  # Lazada
  # =========================

  def run_lazada!
    shops = Shop.where(channel: "lazada", active: true)
    shops = shops.where(id: @shop_id) if @shop_id.present?
    shops = shops.where.not(lazada_credential_id: nil)

    if shops.empty?
      puts({ event: "marketplace.mapping_audit.lazada.no_shops" }.to_json)
      return
    end

    shops.find_each do |shop|
      audit_lazada_shop!(shop)
    end
  end

  def audit_lazada_shop!(shop)
    puts({
      event: "marketplace.mapping_audit.lazada.shop_start",
      shop_id: shop.id,
      shop_code: shop.shop_code,
      from_time: @from_time.iso8601,
      to_time: @now.iso8601
    }.to_json)

    offset = 0
    page = 0
    summary = empty_summary(channel: "lazada", shop: shop)

    loop do
      break if page >= @max_pages

      resp = Marketplace::Lazada::Orders::Search.call!(
        shop: shop,
        update_after: @from_time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        offset: offset,
        limit: DEFAULT_LAZADA_LIMIT
      )

      orders = Array(resp[:rows])
      break if orders.empty?

      page += 1
      summary[:pages] = page
      summary[:search_rows] += orders.size

      order_ids = orders.map { |o| o["order_id"].to_s }.reject(&:blank?)
      items = Marketplace::Lazada::Orders::Items.call!(shop: shop, order_ids: order_ids)
      transformed = Orders::Lazada::Transformer.call(orders: orders, items: items)

      Array(transformed).each do |raw_order|
        summary[:detail_rows] += 1

        Array(raw_order["line_items"]).each do |line|
          result = resolve_lazada_line(shop: shop, line: line)
          absorb_result!(summary, result, line: line)
        end

        if @write
          Orders::Lazada::Upsert.call!(shop: shop, raw_order: raw_order)
          summary[:writes] += 1
        end
      end

      offset += orders.size
      break if orders.size < DEFAULT_LAZADA_LIMIT
    end

    puts(summary.to_json)
  rescue => e
    puts({
      event: "marketplace.mapping_audit.lazada.shop_fail",
      shop_id: shop.id,
      shop_code: shop.shop_code,
      err_class: e.class.name,
      err_message: e.message
    }.to_json)
  end

  def resolve_lazada_line(shop:, line:)
    seller_sku_raw = line["seller_sku"].to_s
    seller_sku = seller_sku_raw.strip

    return {
      state: "blank_seller_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: nil
    } if seller_sku.blank?

    return {
      state: "numeric_seller_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku
    } if seller_sku.match?(/\A\d+\z/)

    mapping = SkuMapping.includes(:sku).find_by(
      channel: "lazada",
      shop_id: shop.id,
      external_sku: seller_sku
    )

    return {
      state: "resolved_by_mapping",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      sku_id: mapping.sku_id,
      sku_code: mapping.sku&.code
    } if mapping.present?

    exact = Sku.find_by(code: seller_sku)
    return {
      state: "resolved_by_exact_code",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      sku_id: exact.id,
      sku_code: exact.code
    } if exact.present?

    normalized = normalize_code(seller_sku_raw)
    normalized_match = normalized.present? ? Sku.find_by(code: normalized) : nil
    return {
      state: "resolved_by_normalized_code",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      normalized_sku: normalized,
      sku_id: normalized_match.id,
      sku_code: normalized_match.code
    } if normalized_match.present?

    {
      state: "unresolved_text_sku",
      seller_sku_raw: seller_sku_raw,
      seller_sku: seller_sku,
      normalized_sku: normalized
    }
  end

  # =========================
  # Shared
  # =========================

  def normalize_code(value)
    value.to_s.gsub(/\s+/, "").strip.presence
  end

  def empty_summary(channel:, shop:)
    {
      event: "marketplace.mapping_audit.shop_summary",
      channel: channel,
      shop_id: shop.id,
      shop_code: shop.shop_code,
      lookback_hours: @lookback_hours,
      pages: 0,
      search_rows: 0,
      detail_rows: 0,
      lines_total: 0,
      resolved_by_mapping: 0,
      resolved_by_exact_code: 0,
      resolved_by_normalized_code: 0,
      numeric_seller_sku: 0,
      blank_seller_sku: 0,
      blank_seller_sku_with_platform_sku_id: 0,
      unresolved_text_sku: 0,
      writes: 0,
      samples: []
    }
  end

  def absorb_result!(summary, result, line:)
    summary[:lines_total] += 1
    key = result[:state].to_sym
    summary[key] += 1 if summary.key?(key)

    return unless keep_sample?(summary, result)

    summary[:samples] << {
      state: result[:state],
      seller_sku_raw: result[:seller_sku_raw],
      seller_sku: result[:seller_sku],
      normalized_sku: result[:normalized_sku],
      platform_sku_id: result[:platform_sku_id],
      line_id: line["id"].to_s.presence,
      display_status: line["display_status"].to_s.presence,
      sku_name: line["sku_name"].to_s.presence
    }
  end

  def keep_sample?(summary, result)
    interesting = %w[
      resolved_by_normalized_code
      numeric_seller_sku
      blank_seller_sku
      blank_seller_sku_with_platform_sku_id
      unresolved_text_sku
    ]
    interesting.include?(result[:state]) && summary[:samples].size < 20
  end
end

MarketplaceMappingAudit.run!
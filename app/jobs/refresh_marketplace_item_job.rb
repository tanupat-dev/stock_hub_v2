# frozen_string_literal: true

class RefreshMarketplaceItemJob < ApplicationJob
  queue_as :default

  def perform(shop_id, external_variant_id)
    shop = Shop.find(shop_id)

    case shop.channel
    when "tiktok"
      refresh_tiktok_variant!(shop, external_variant_id)
    when "lazada"
      refresh_lazada_variant!(shop, external_variant_id)
    end

    Rails.logger.info(
      {
        event: "refresh_marketplace_item_job.done",
        shop_id: shop.id,
        channel: shop.channel,
        external_variant_id: external_variant_id
      }.to_json
    )
  rescue => e
    Rails.logger.error(
      {
        event: "refresh_marketplace_item_job.fail",
        shop_id: shop_id,
        external_variant_id: external_variant_id,
        err: e.message
      }.to_json
    )
  end

  private

  def refresh_tiktok_variant!(shop, external_variant_id)
    resp = Marketplace::Tiktok::Catalog::List.call!(
      shop: shop,
      page_size: 50,
      max_pages: 5,
      strict: true,
      dry_run: false
    )

    items = Array(resp[:items]).select do |it|
      it[:external_variant_id].to_s == external_variant_id.to_s
    end

    return if items.empty?

    Catalog::UpsertMarketplaceItems.call!(
      shop: shop,
      items: items
    )
  end

  def refresh_lazada_variant!(shop, external_variant_id)
    item = MarketplaceItem.find_by!(
      shop_id: shop.id,
      external_variant_id: external_variant_id.to_s
    )

    seller_sku = item.external_sku.to_s.strip
    return if seller_sku.blank?

    resp = Marketplace::Lazada::Catalog::List.call!(
      shop: shop,
      sku_seller_list: [ seller_sku ]
    )

    products = Array(resp[:rows])
    return if products.empty?

    Catalog::UpsertLazadaMarketplaceItems.call!(
      shop: shop,
      products: products
    )
  end
end

# frozen_string_literal: true

class RefreshMarketplaceItemJob < ApplicationJob
  queue_as :default

  def perform(shop_id, external_variant_id)
    shop = Shop.find(shop_id)

    case shop.channel
    when "tiktok"
      resp = Marketplace::Tiktok::Catalog::List.call!(
        shop: shop,
        page_size: 1,
        variant_ids: [ external_variant_id ]
      )

      items = resp[:items] || []
      Catalog::UpsertMarketplaceItems.call!(shop: shop, items: items)

    when "lazada"
      resp = Marketplace::Lazada::Catalog::List.call!(
        shop: shop,
        sku_ids: [ external_variant_id ]
      )

      products = resp[:products] || []
      Catalog::UpsertLazadaMarketplaceItems.call!(shop: shop, products: products)
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
end

# frozen_string_literal: true

class SyncSkuMasterJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(shop_id, enqueue_sync_stock: false, dry_run: false)
    shop = Shop.find(shop_id)

    unless shop.active?
      return {
        ok: true,
        skipped: true,
        reason: "inactive_shop",
        shop_id: shop.id
      }
    end

    unless supported_channel?(shop.channel)
      return {
        ok: true,
        skipped: true,
        reason: "unsupported_channel",
        shop_id: shop.id,
        channel: shop.channel
      }
    end

    # ✅ IMPORTANT: mapping service will NOT auto-create SKU.
    Catalog::SyncSkuMasterFromCatalog.call!(
      shop: shop,
      items: nil,              # load from marketplace_items for this shop
      match_by: :code,         # sku.code == external_sku
      enqueue_sync_stock: enqueue_sync_stock,
      dry_run: dry_run
    )
  end

  private

  def supported_channel?(channel)
    %w[tiktok lazada shopee].include?(channel)
  end
end

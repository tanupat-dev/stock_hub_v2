# frozen_string_literal: true

class ImportShopeeOrdersJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(shop_id, filepath, source_filename: nil)
    shop = Shop.find(shop_id)
    raise "shop #{shop.id} is not shopee" unless shop.channel == "shopee"

    Shopee::ImportOrders.call!(
      shop: shop,
      filepath: filepath,
      source_filename: source_filename
    )
  end
end

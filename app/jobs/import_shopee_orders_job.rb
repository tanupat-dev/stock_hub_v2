# frozen_string_literal: true

class ImportShopeeOrdersJob < ApplicationJob
  queue_as :imports

  discard_on ActiveRecord::RecordNotFound

  def perform(batch_id, rows)
    batch = FileBatch.find(batch_id)
    shop = batch.shop

    raise "shop #{shop.id} is not shopee" unless shop.channel == "shopee"

    Shopee::ImportOrders.call!(
      shop: shop,
      rows: rows,
      source_filename: batch.source_filename,
      batch: batch
    )
  end
end

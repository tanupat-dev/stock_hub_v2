class CreateMarketplaceItems < ActiveRecord::Migration[8.0]
  def change
    create_table :marketplace_items do |t|
      t.references :shop, null: false, foreign_key: true

      t.string  :channel, null: false
      t.string  :external_product_id
      t.string  :external_variant_id
      t.string  :external_sku
      t.string  :title
      t.string  :status
      t.integer :available_stock, null: false, default: 0

      t.jsonb   :raw_payload, null: false, default: {}
      t.datetime :synced_at

      t.timestamps
    end

    add_index :marketplace_items,
      [:shop_id, :external_variant_id],
      unique: true,
      where: "external_variant_id IS NOT NULL",
      name: "uniq_marketplace_variant"

    add_index :marketplace_items,
      [:shop_id, :external_sku],
      where: "external_sku IS NOT NULL",
      name: "index_marketplace_items_on_sku"
  end
end
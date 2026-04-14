class CreateSkuMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :sku_mappings do |t|
      t.string :channel, null: false
      t.references :shop, null: false, foreign_key: true

      t.string :external_sku, null: false
      t.references :sku, null: false, foreign_key: true

      t.timestamps
    end

    add_index :sku_mappings, [:channel, :shop_id, :external_sku],
              unique: true, name: "uniq_sku_mappings"

    add_index :sku_mappings, [:sku_id, :shop_id]
  end
end
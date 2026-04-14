class CreateShops < ActiveRecord::Migration[8.0]
  def change
    create_table :shops do |t|
      t.string :channel, null: false # tiktok/lazada/shopee/pos
      t.string :shop_code, null: false # external_shop_id หรือ code ที่มึงตั้ง
      t.string :name

      # polling pointers (เก็บไว้ก่อน)
      t.bigint :last_seen_update_time
      t.datetime :last_polled_at

      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :shops, [:channel, :shop_code], unique: true
    add_index :shops, [:channel, :active]
  end
end
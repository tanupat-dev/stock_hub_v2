# frozen_string_literal: true

class CreateShopSkuSyncStates < ActiveRecord::Migration[8.0]
  def change
    create_table :shop_sku_sync_states do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :sku,  null: false, foreign_key: true

      t.integer  :last_pushed_available
      t.datetime :last_pushed_at

      t.integer  :fail_count, default: 0, null: false
      t.datetime :last_failed_at
      t.text     :last_error

      t.timestamps
    end

    add_index :shop_sku_sync_states, %i[shop_id sku_id], unique: true
    add_index :shop_sku_sync_states, :last_pushed_at
  end
end
class AddLazadaOrdersPollCursorToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :lazada_orders_last_seen_update_time, :bigint
    add_column :shops, :lazada_orders_last_polled_at, :datetime

    add_index :shops, :lazada_orders_last_seen_update_time, name: "idx_shops_lazada_orders_cursor"
    add_index :shops, :lazada_orders_last_polled_at, name: "idx_shops_lazada_orders_polled_at"
  end
end

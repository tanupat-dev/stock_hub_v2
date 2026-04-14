# frozen_string_literal: true

class AddReturnsPollCursorsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :tiktok_returns_last_seen_update_time, :bigint
    add_column :shops, :tiktok_returns_last_polled_at, :datetime

    add_column :shops, :lazada_returns_last_seen_update_time, :bigint
    add_column :shops, :lazada_returns_last_polled_at, :datetime

    add_index :shops, :tiktok_returns_last_seen_update_time
    add_index :shops, :tiktok_returns_last_polled_at

    add_index :shops, :lazada_returns_last_seen_update_time
    add_index :shops, :lazada_returns_last_polled_at
  end
end

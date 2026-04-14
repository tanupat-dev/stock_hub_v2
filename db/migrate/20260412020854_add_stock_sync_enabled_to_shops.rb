# frozen_string_literal: true

class AddStockSyncEnabledToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :stock_sync_enabled, :boolean, null: false, default: false
    add_index :shops, :stock_sync_enabled
  end
end

class AddSyncFailureTrackingToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :sync_fail_count, :integer, default: 0, null: false
    add_column :shops, :last_sync_failed_at, :datetime
    add_column :shops, :last_sync_error, :text
  end
end
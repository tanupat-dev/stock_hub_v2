# frozen_string_literal: true

class CreateStockSyncRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_sync_requests do |t|
      t.references :sku, null: false, foreign_key: true, index: { unique: true }

      t.string :status, null: false, default: "pending"
      t.string :last_reason
      t.datetime :first_requested_at, null: false
      t.datetime :last_requested_at, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :last_enqueued_at
      t.datetime :last_processed_at
      t.text :last_error

      t.timestamps
    end

    add_index :stock_sync_requests, [ :status, :scheduled_for ]
  end
end

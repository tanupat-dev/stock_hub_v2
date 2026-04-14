# frozen_string_literal: true

class CreateShippingExportBatchItems < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_export_batch_items do |t|
      t.references :shipping_export_batch, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.string :channel, null: false
      t.bigint :shop_id, null: false
      t.string :external_order_id, null: false
      t.string :order_status_snapshot
      t.datetime :exported_at
      t.integer :row_index
      t.jsonb :payload_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :shipping_export_batch_items,
              [ :shipping_export_batch_id, :order_id ],
              unique: true,
              name: "idx_ship_export_batch_items_batch_order"

    add_index :shipping_export_batch_items, :channel
    add_index :shipping_export_batch_items, :shop_id
    add_index :shipping_export_batch_items, :external_order_id
  end
end

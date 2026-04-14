# frozen_string_literal: true

class CreateShippingExportBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_export_batches do |t|
      t.string :export_key, null: false
      t.string :status, null: false, default: "building"
      t.string :template_name, null: false
      t.jsonb :filters_snapshot, null: false, default: {}
      t.integer :row_count, null: false, default: 0
      t.string :file_path
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :error_message
      t.jsonb :debug_meta, null: false, default: {}

      t.timestamps
    end

    add_index :shipping_export_batches, :export_key, unique: true
    add_index :shipping_export_batches, :status
    add_index :shipping_export_batches, :requested_at
  end
end

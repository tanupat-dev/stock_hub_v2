# frozen_string_literal: true

class CreateSkuImportBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :sku_import_batches do |t|
      t.string :status, null: false, default: "pending"
      t.boolean :dry_run, null: false, default: false
      t.string :stock_mode, null: false, default: "skip"
      t.string :original_filename
      t.integer :total_rows, null: false, default: 0
      t.integer :upsert_rows, null: false, default: 0
      t.integer :stock_updated, null: false, default: 0
      t.integer :stock_failed, null: false, default: 0
      t.jsonb :result, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :sku_import_batches, :status
    add_index :sku_import_batches, :created_at
  end
end

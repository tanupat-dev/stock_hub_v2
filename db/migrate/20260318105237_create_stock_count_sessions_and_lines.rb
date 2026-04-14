# frozen_string_literal: true

class CreateStockCountSessionsAndLines < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_count_sessions do |t|
      t.references :shop, null: false, foreign_key: true

      t.string :session_number, null: false
      t.string :status, null: false, default: "open"
      t.string :idempotency_key, null: false

      t.datetime :confirmed_at
      t.datetime :cancelled_at

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :stock_count_sessions, :session_number, unique: true
    add_index :stock_count_sessions, :status
    add_index :stock_count_sessions, :idempotency_key, unique: true
    add_index :stock_count_sessions, [ :shop_id, :created_at ]

    create_table :stock_count_lines do |t|
      t.references :stock_count_session, null: false, foreign_key: true
      t.references :sku, null: false, foreign_key: true

      t.string :barcode_snapshot
      t.string :sku_code_snapshot, null: false

      t.integer :system_qty_snapshot, null: false, default: 0
      t.integer :counted_qty, null: false, default: 0
      t.integer :diff_qty, null: false, default: 0

      t.string :status, null: false, default: "pending"
      t.string :idempotency_key, null: false

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :stock_count_lines, :idempotency_key, unique: true
    add_index :stock_count_lines, :status
    add_index :stock_count_lines, [ :stock_count_session_id, :sku_id ], unique: true, name: "idx_stock_count_lines_session_sku"

    add_check_constraint :stock_count_lines,
                         "system_qty_snapshot >= 0",
                         name: "chk_stock_count_lines_system_qty_non_negative"

    add_check_constraint :stock_count_lines,
                         "counted_qty >= 0",
                         name: "chk_stock_count_lines_counted_qty_non_negative"
  end
end

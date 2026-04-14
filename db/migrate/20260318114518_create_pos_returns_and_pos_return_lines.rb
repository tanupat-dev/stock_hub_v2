# frozen_string_literal: true

class CreatePosReturnsAndPosReturnLines < ActiveRecord::Migration[8.0]
  def change
    create_table :pos_returns do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :pos_sale, null: false, foreign_key: true

      t.string :return_number, null: false
      t.string :status, null: false, default: "open"
      t.string :idempotency_key, null: false

      t.datetime :completed_at
      t.datetime :cancelled_at

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :pos_returns, :return_number, unique: true
    add_index :pos_returns, :status
    add_index :pos_returns, :idempotency_key, unique: true
    add_index :pos_returns, [ :shop_id, :created_at ]
    add_index :pos_returns, [ :pos_sale_id, :created_at ]

    create_table :pos_return_lines do |t|
      t.references :pos_return, null: false, foreign_key: true
      t.references :pos_sale_line, null: false, foreign_key: true
      t.references :sku, null: false, foreign_key: true

      t.integer :quantity, null: false
      t.string :barcode_snapshot
      t.string :sku_code_snapshot, null: false

      t.string :idempotency_key, null: false
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :pos_return_lines, :idempotency_key, unique: true
    add_index :pos_return_lines, [ :pos_return_id, :sku_id ]
    add_index :pos_return_lines, [ :pos_sale_line_id, :created_at ]

    add_check_constraint :pos_return_lines,
                         "quantity > 0",
                         name: "chk_pos_return_lines_quantity_positive"
  end
end

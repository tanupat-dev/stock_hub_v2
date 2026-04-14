# frozen_string_literal: true

class CreatePosSalesAndPosSaleLines < ActiveRecord::Migration[8.0]
  def change
    create_table :pos_sales do |t|
      t.references :shop, null: false, foreign_key: true

      t.string :sale_number, null: false
      t.string :status, null: false, default: "cart"

      t.integer :item_count, null: false, default: 0

      t.string :idempotency_key, null: false

      t.datetime :checked_out_at
      t.datetime :voided_at

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :pos_sales, :sale_number, unique: true
    add_index :pos_sales, :status
    add_index :pos_sales, :checked_out_at
    add_index :pos_sales, :voided_at
    add_index :pos_sales, :idempotency_key, unique: true
    add_index :pos_sales, [ :shop_id, :created_at ]
    add_index :pos_sales, [ :shop_id, :status, :created_at ]

    add_check_constraint :pos_sales,
                         "item_count >= 0",
                         name: "chk_pos_sales_item_count_non_negative"

    create_table :pos_sale_lines do |t|
      t.references :pos_sale, null: false, foreign_key: true
      t.references :sku, null: false, foreign_key: true

      t.string :status, null: false, default: "active"

      t.string :barcode_snapshot
      t.string :sku_code_snapshot, null: false
      t.string :title_snapshot

      t.integer :quantity, null: false, default: 1

      t.string :idempotency_key, null: false
      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :pos_sale_lines, :status
    add_index :pos_sale_lines, :idempotency_key, unique: true
    add_index :pos_sale_lines, [ :pos_sale_id, :sku_id ]
    add_index :pos_sale_lines, [ :pos_sale_id, :created_at ]

    add_check_constraint :pos_sale_lines,
                         "quantity > 0",
                         name: "chk_pos_sale_lines_quantity_positive"
  end
end

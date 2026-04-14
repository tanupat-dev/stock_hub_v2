class CreateReturnScans < ActiveRecord::Migration[8.0]
  def change
    create_table :return_scans do |t|
      t.bigint :return_shipment_id, null: false
      t.bigint :order_line_id, null: false
      t.bigint :sku_id, null: false

      t.integer :quantity, null: false, default: 1
      t.string  :idempotency_key, null: false
      t.jsonb   :meta, null: false, default: {}
      t.datetime :scanned_at, null: false

      t.timestamps
    end

    add_foreign_key :return_scans, :return_shipments
    add_foreign_key :return_scans, :order_lines
    add_foreign_key :return_scans, :skus

    add_index :return_scans, :idempotency_key, unique: true
    add_index :return_scans, %i[return_shipment_id order_line_id]
    add_check_constraint :return_scans, "quantity > 0", name: "chk_return_scans_qty_positive"
  end
end
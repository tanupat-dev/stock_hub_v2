class CreateOrderLines < ActiveRecord::Migration[8.0]
  def change
    create_table :order_lines do |t|
      t.references :order, null: false, foreign_key: true

      t.string :external_line_id
      t.string :external_sku # เก็บไว้ช่วย debug/map (optional แต่มีประโยชน์)

      t.references :sku, foreign_key: true # map ได้ทีหลัง (nullable)

      t.integer :quantity, null: false, default: 1
      t.string :status # line status ถ้ามี

      # หัวใจ idempotent กัน reserve/release ซ้ำ
      t.string :idempotency_key, null: false

      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps
    end

    add_index :order_lines, :idempotency_key, unique: true
    add_index :order_lines, [:order_id, :external_line_id],
              unique: true,
              where: "external_line_id IS NOT NULL",
              name: "uniq_order_lines_when_external_line"

    add_check_constraint :order_lines, "quantity > 0", name: "chk_order_line_qty_positive"
  end
end
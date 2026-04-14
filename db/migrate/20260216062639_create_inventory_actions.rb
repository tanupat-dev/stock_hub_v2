class CreateInventoryActions < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_actions do |t|
      t.references :sku, null: false, foreign_key: true
      t.references :order_line, null: true, foreign_key: true

      t.string :action_type, null: false # reserve/release
      t.integer :quantity, null: false, default: 1
      t.string :idempotency_key, null: false

      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end

    add_index :inventory_actions, :idempotency_key, unique: true
    add_index :inventory_actions, [:sku_id, :created_at]
    add_check_constraint :inventory_actions, "quantity > 0", name: "chk_inventory_action_qty_positive"
  end
end
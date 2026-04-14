class CreateOversellAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :oversell_allocations do |t|
      t.references :oversell_incident, null: false, foreign_key: true
      t.references :order_line, null: false, foreign_key: true
      t.references :sku, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end

    add_index :oversell_allocations, [:sku_id, :order_line_id]
    add_check_constraint :oversell_allocations, "quantity > 0", name: "chk_oversell_alloc_qty_positive"
  end
end

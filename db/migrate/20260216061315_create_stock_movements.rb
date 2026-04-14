class CreateStockMovements < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_movements do |t|
      t.references :sku, null: false, foreign_key: true
      t.integer :delta_on_hand, null: false
      t.string :reason, null: false
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end

    add_index :stock_movements, :reason
    add_index :stock_movements, [:sku_id, :created_at]
  end
end
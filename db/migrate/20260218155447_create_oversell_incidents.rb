class CreateOversellIncidents < ActiveRecord::Migration[8.0]
  def change
    create_table :oversell_incidents do |t|
      t.references :sku, null: false, foreign_key: true
      t.integer :shortfall_qty, null: false
      t.string :trigger, null: false # e.g. "stock_adjust"
      t.string :status, null: false, default: "open" # open/resolved/ignored
      t.jsonb :meta, null: false, default: {}
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :oversell_incidents, [:sku_id, :status]
  end
end
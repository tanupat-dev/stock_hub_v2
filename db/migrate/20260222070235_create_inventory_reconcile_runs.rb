class CreateInventoryReconcileRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_reconcile_runs do |t|
      t.references :shop, null: false, foreign_key: true
      t.integer :mismatched_count, default: 0, null: false
      t.integer :unmapped_count, default: 0, null: false
      t.integer :pushed_count, default: 0, null: false
      t.text :error
      t.datetime :ran_at, null: false

      t.timestamps
    end
  end
end
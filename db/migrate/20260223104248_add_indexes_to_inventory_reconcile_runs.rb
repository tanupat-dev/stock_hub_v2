# frozen_string_literal: true

class AddIndexesToInventoryReconcileRuns < ActiveRecord::Migration[8.0]
  def change
    # เผื่อดู history ล่าสุดของ shop เร็ว ๆ
    add_index :inventory_reconcile_runs, :ran_at unless index_exists?(:inventory_reconcile_runs, :ran_at)

    # ใช้บ่อย: where shop_id = ? order by ran_at desc
    unless index_exists?(:inventory_reconcile_runs, [:shop_id, :ran_at], name: "index_inventory_reconcile_runs_on_shop_and_ran_at")
      add_index :inventory_reconcile_runs, [:shop_id, :ran_at], name: "index_inventory_reconcile_runs_on_shop_and_ran_at"
    end
  end
end
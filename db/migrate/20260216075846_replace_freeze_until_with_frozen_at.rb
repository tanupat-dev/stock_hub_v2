class ReplaceFreezeUntilWithFrozenAt < ActiveRecord::Migration[8.0]
  def change
    if index_exists?(:inventory_balances, :freeze_until)
      remove_index :inventory_balances, :freeze_until
    end

    if column_exists?(:inventory_balances, :freeze_until)
      remove_column :inventory_balances, :freeze_until, :datetime
    end

    unless column_exists?(:inventory_balances, :frozen_at)
      add_column :inventory_balances, :frozen_at, :datetime
      add_index  :inventory_balances, :frozen_at
    end
  end
end
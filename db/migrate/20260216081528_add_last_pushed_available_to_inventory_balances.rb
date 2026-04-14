class AddLastPushedAvailableToInventoryBalances < ActiveRecord::Migration[8.0]
  def change
    add_column :inventory_balances, :last_pushed_available, :integer
    add_column :inventory_balances, :last_pushed_at, :datetime
  end
end
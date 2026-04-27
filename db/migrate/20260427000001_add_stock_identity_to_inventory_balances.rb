class AddStockIdentityToInventoryBalances < ActiveRecord::Migration[8.0]
  def change
    add_column :inventory_balances, :stock_identity_id, :bigint
    add_index  :inventory_balances, :stock_identity_id, unique: true

    add_foreign_key :inventory_balances, :stock_identities
  end
end

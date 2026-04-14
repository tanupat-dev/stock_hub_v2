class CreateInventoryBalances < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_balances do |t|
      t.references :sku, null: false, foreign_key: true, index: { unique: true }
      t.integer :on_hand, null: false, default: 0
      t.integer :reserved, null: false, default: 0

      t.datetime :freeze_until
      t.string :freeze_reason
      t.timestamps
    end

    add_index :inventory_balances, :freeze_until
    add_check_constraint :inventory_balances, "on_hand >= 0", name: "chk_on_hand_non_negative"
    add_check_constraint :inventory_balances, "reserved >= 0", name: "chk_reserved_non_negative"
    add_check_constraint :inventory_balances, "(on_hand - reserved) >= 0", name: "chk_available_non_negative"
  end
end
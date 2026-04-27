class CreateStockIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_identities do |t|
      t.string :code
      t.timestamps
    end

    add_index :stock_identities, :code, unique: true

    add_column :skus, :stock_identity_id, :bigint
    add_index  :skus, :stock_identity_id

    add_foreign_key :skus, :stock_identities
  end
end

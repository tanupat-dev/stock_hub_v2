class CreateSkus < ActiveRecord::Migration[8.0]
  def change
    create_table :skus do |t|
      t.string :code, null: false
      t.string :barcode, null: false
      t.string :brand
      t.string :model
      t.string :color
      t.string :size

      t.boolean :active, null: false, default: true
      t.datetime :archived_at

      t.integer :buffer_quantity, null: false, default: 3
      t.timestamps
    end

    add_index :skus, :code, unique: true
    add_index :skus, :barcode, unique: true
    add_index :skus, :active
    add_index :skus, :archived_at
    add_index :skus, :buffer_quantity

    add_check_constraint :skus, "buffer_quantity >= 0", name: "chk_sku_buffer_non_negative"
  end
end
# frozen_string_literal: true

class AddTiktokFieldsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :external_shop_id, :string
    add_column :shops, :shop_cipher, :string
    add_column :shops, :region, :string
    add_column :shops, :seller_type, :string

    add_reference :shops, :tiktok_credential, foreign_key: true

    add_index :shops, :external_shop_id
    add_index :shops, :shop_cipher
  end
end
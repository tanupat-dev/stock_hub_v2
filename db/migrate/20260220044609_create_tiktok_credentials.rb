# frozen_string_literal: true

class CreateTiktokCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :tiktok_credentials do |t|
      t.string  :open_id, null: false
      t.integer :user_type, null: false # 0 seller
      t.string  :seller_name
      t.string  :seller_base_region

      t.text    :access_token, null: false
      t.datetime :access_token_expires_at, null: false

      t.text    :refresh_token, null: false
      t.datetime :refresh_token_expires_at, null: false

      t.jsonb   :granted_scopes, default: [], null: false
      t.boolean :active, default: true, null: false
      t.text    :last_error

      t.timestamps
    end

    add_index :tiktok_credentials, :open_id, unique: true
  end
end
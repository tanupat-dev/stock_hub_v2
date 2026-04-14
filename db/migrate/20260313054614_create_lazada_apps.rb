# frozen_string_literal: true

class CreateLazadaApps < ActiveRecord::Migration[8.0]
  def change
    create_table :lazada_apps do |t|
      t.string :code, null: false
      t.string :app_key, null: false
      t.string :app_secret, null: false
      t.string :auth_host, null: false, default: "https://auth.lazada.com"
      t.string :api_host, null: false, default: "https://api.lazada.co.th"
      t.string :callback_url
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :lazada_apps, :code, unique: true
    add_index :lazada_apps, :active
  end
end

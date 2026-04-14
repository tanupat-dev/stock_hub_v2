# frozen_string_literal: true

class CreateTiktokApps < ActiveRecord::Migration[8.0]
  def change
    create_table :tiktok_apps do |t|
      t.string :code, null: false # เช่น "tiktok_1", "tiktok_2"
      t.string :auth_region, null: false, default: "ROW" # ROW/US
      t.string :service_id, null: false

      t.string :app_key, null: false
      t.string :app_secret, null: false

      t.string :open_api_host, null: false, default: "https://open-api.tiktokglobalshop.com"
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :tiktok_apps, :code, unique: true
    add_index :tiktok_apps, :active
  end
end
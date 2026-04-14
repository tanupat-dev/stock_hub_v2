# frozen_string_literal: true

class AddUniqueIndexToTiktokCredentialsOnAppAndOpenId < ActiveRecord::Migration[8.0]
  def change
    unless index_exists?(:tiktok_credentials, [ :tiktok_app_id, :open_id ], unique: true, name: "index_tiktok_credentials_on_tiktok_app_id_and_open_id")
      add_index :tiktok_credentials,
                [ :tiktok_app_id, :open_id ],
                unique: true,
                name: "index_tiktok_credentials_on_tiktok_app_id_and_open_id"
    end
  end
end

# frozen_string_literal: true

class RemoveUniqueIndexOnTiktokCredentialsOpenId < ActiveRecord::Migration[8.0]
  def change
    # Multi-app should be unique on [tiktok_app_id, open_id]
    # Having a global unique on open_id will block same open_id across apps.
    remove_index :tiktok_credentials, :open_id if index_exists?(:tiktok_credentials, :open_id)
  end
end

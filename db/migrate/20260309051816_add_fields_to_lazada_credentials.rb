# frozen_string_literal: true

class AddFieldsToLazadaCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :lazada_credentials, :refresh_expires_at, :datetime
    add_column :lazada_credentials, :account, :string
    add_column :lazada_credentials, :account_platform, :string
    add_column :lazada_credentials, :country, :string
    add_column :lazada_credentials, :seller_id, :string
    add_column :lazada_credentials, :user_id, :string
    add_column :lazada_credentials, :short_code, :string
    add_column :lazada_credentials, :raw_payload, :jsonb, default: {}, null: false

    add_index :lazada_credentials, :seller_id
    add_index :lazada_credentials, :short_code
  end
end

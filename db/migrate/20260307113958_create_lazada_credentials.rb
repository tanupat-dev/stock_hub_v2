class CreateLazadaCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :lazada_credentials do |t|
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at

      t.timestamps
    end
  end
end

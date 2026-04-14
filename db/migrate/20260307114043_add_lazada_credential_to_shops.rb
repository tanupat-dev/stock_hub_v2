class AddLazadaCredentialToShops < ActiveRecord::Migration[8.0]
  def change
    add_reference :shops, :lazada_credential, foreign_key: true
  end
end

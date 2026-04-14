# frozen_string_literal: true

class AddLazadaAppToShops < ActiveRecord::Migration[8.0]
  def change
    add_reference :shops, :lazada_app, foreign_key: true
  end
end

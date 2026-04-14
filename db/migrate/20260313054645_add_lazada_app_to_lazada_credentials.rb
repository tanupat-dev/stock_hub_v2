# frozen_string_literal: true

class AddLazadaAppToLazadaCredentials < ActiveRecord::Migration[8.0]
  def change
    add_reference :lazada_credentials, :lazada_app, foreign_key: true
  end
end

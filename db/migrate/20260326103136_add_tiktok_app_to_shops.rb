# frozen_string_literal: true

class AddTiktokAppToShops < ActiveRecord::Migration[8.0]
  def change
    add_reference :shops, :tiktok_app, foreign_key: true, null: true
  end
end

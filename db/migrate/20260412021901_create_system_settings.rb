# frozen_string_literal: true

class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :system_settings do |t|
      t.string :key, null: false
      t.text :value_text
      t.timestamps
    end

    add_index :system_settings, :key, unique: true
  end
end

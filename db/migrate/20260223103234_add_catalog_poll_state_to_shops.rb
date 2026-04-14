# frozen_string_literal: true

class AddCatalogPollStateToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :catalog_last_page_token, :string
    add_column :shops, :catalog_last_polled_at, :datetime
    add_column :shops, :catalog_last_total_count, :integer
    add_column :shops, :catalog_last_error, :text
    add_column :shops, :catalog_fail_count, :integer, default: 0, null: false

    add_index :shops, :catalog_last_polled_at
  end
end
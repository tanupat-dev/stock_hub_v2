# frozen_string_literal: true

class AddExternalVariantIdToSkuMappings < ActiveRecord::Migration[8.0]
  def change
    add_column :sku_mappings, :external_variant_id, :string

    add_index :sku_mappings,
              %i[channel shop_id external_variant_id],
              unique: true,
              where: "external_variant_id IS NOT NULL",
              name: "uniq_sku_mappings_variant"
  end
end
# frozen_string_literal: true

class RelaxSkuBarcodePolicy < ActiveRecord::Migration[8.0]
  def up
    change_column_null :skus, :barcode, true

    execute <<~SQL
      UPDATE skus
      SET barcode = NULL
      WHERE barcode LIKE 'AUTO-%';
    SQL
  end

  def down
    execute <<~SQL
      UPDATE skus
      SET barcode = 'AUTO-' || SUBSTRING(md5(code) FROM 1 FOR 12)
      WHERE barcode IS NULL;
    SQL

    change_column_null :skus, :barcode, false
  end
end

# frozen_string_literal: true

class AddReturnDebugIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :return_shipment_lines, :order_line_id unless index_exists?(:return_shipment_lines, :order_line_id)
    add_index :return_shipment_lines, :sku_id unless index_exists?(:return_shipment_lines, :sku_id)
    add_index :return_scans, :sku_id unless index_exists?(:return_scans, :sku_id)
    add_index :return_scans, :scanned_at unless index_exists?(:return_scans, :scanned_at)
  end
end

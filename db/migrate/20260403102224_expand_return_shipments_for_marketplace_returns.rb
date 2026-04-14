# frozen_string_literal: true

class ExpandReturnShipmentsForMarketplaceReturns < ActiveRecord::Migration[8.0]
  def up
    change_column_null :return_shipments, :order_id, true

    add_column :return_shipments, :requested_at, :datetime
    add_column :return_shipments, :return_carrier_method, :string
    add_column :return_shipments, :return_delivery_status, :string
    add_column :return_shipments, :returned_delivered_at, :datetime
    add_column :return_shipments, :buyer_username, :string
    add_column :return_shipments, :raw_payload, :jsonb, default: {}, null: false

    add_index :return_shipments, :status_store
    add_index :return_shipments, :status_marketplace
    add_index :return_shipments, :requested_at
    add_index :return_shipments, :returned_delivered_at

    create_table :return_shipment_lines do |t|
      t.references :return_shipment, null: false, foreign_key: true
      t.references :order_line, null: true, foreign_key: true
      t.references :sku, null: true, foreign_key: true

      t.string :external_line_id
      t.string :sku_code_snapshot, null: false
      t.integer :qty_returned, null: false, default: 1
      t.jsonb :raw_payload, default: {}, null: false

      t.timestamps
    end

    add_index :return_shipment_lines, :sku_code_snapshot
    add_index :return_shipment_lines, [ :return_shipment_id, :external_line_id ],
              unique: true,
              where: "external_line_id IS NOT NULL",
              name: "uniq_return_shipment_lines_external_line"
    add_index :return_shipment_lines, [ :return_shipment_id, :order_line_id, :sku_code_snapshot ],
              name: "idx_return_shipment_lines_lookup"

    execute <<~SQL
      ALTER TABLE return_shipment_lines
      ADD CONSTRAINT chk_return_shipment_lines_qty_positive
      CHECK (qty_returned > 0);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE return_shipment_lines
      DROP CONSTRAINT IF EXISTS chk_return_shipment_lines_qty_positive;
    SQL

    remove_index :return_shipment_lines, name: "idx_return_shipment_lines_lookup"
    remove_index :return_shipment_lines, name: "uniq_return_shipment_lines_external_line"
    remove_index :return_shipment_lines, :sku_code_snapshot

    drop_table :return_shipment_lines

    remove_index :return_shipments, :returned_delivered_at
    remove_index :return_shipments, :requested_at
    remove_index :return_shipments, :status_marketplace
    remove_index :return_shipments, :status_store

    remove_column :return_shipments, :raw_payload
    remove_column :return_shipments, :buyer_username
    remove_column :return_shipments, :returned_delivered_at
    remove_column :return_shipments, :return_delivery_status
    remove_column :return_shipments, :return_carrier_method
    remove_column :return_shipments, :requested_at

    change_column_null :return_shipments, :order_id, false
  end
end

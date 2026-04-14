# frozen_string_literal: true

class FixReturnShipmentTrackingUniqueness < ActiveRecord::Migration[8.0]
  def up
    remove_index :return_shipments, name: :uniq_return_shipments_by_tracking, if_exists: true

    add_index :return_shipments, :tracking_number, name: :index_return_shipments_on_tracking_number unless index_exists?(:return_shipments, :tracking_number, name: :index_return_shipments_on_tracking_number)
  end

  def down
    remove_index :return_shipments, name: :index_return_shipments_on_tracking_number, if_exists: true

    add_index :return_shipments, :tracking_number, unique: true, name: :uniq_return_shipments_by_tracking unless index_exists?(:return_shipments, :tracking_number, name: :uniq_return_shipments_by_tracking)
  end
end

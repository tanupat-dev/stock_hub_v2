# frozen_string_literal: true

module Inventory
  class BalanceFetcher
    def self.fetch_for_update!(sku:)
      raise ArgumentError, "sku is required" if sku.nil?

      loop do
        balance = InventoryBalance.lock.find_by(sku_id: sku.id)
        return balance if balance

        begin
          sku.create_inventory_balance!(on_hand: 0, reserved: 0)
        rescue ActiveRecord::RecordNotUnique
          # another transaction created it first
        end
      end
    end
  end
end

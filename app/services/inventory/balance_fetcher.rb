# frozen_string_literal: true

module Inventory
  class BalanceFetcher
    def self.fetch_for_update!(sku:)
      raise ArgumentError, "sku is required" if sku.nil?

      stock_identity_id = sku.stock_identity_id
      raise "stock_identity_id missing for sku=#{sku.id} (should not happen)" if stock_identity_id.blank?

      loop do
        balance = InventoryBalance.lock.find_by(stock_identity_id: stock_identity_id)

        return balance if balance

        begin
          InventoryBalance.create!(
            stock_identity_id: stock_identity_id,
            sku_id: sku.id,
            on_hand: 0,
            reserved: 0
          )
        rescue ActiveRecord::RecordNotUnique
          # retry
        end
      end
    end
  end
end

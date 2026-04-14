# frozen_string_literal: true

module Inventory
  class StockIn
    def self.call!(sku:, quantity:, idempotency_key:, meta: {})
      new(sku:, quantity:, idempotency_key:, meta:).call!
    end

    def initialize(sku:, quantity:, idempotency_key:, meta:)
      @sku = sku
      @quantity = Integer(quantity)
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "quantity must be > 0" if @quantity <= 0
      raise ArgumentError, "sku is required" if @sku.nil?

      before = nil
      after = nil
      result = nil

      InventoryAction.transaction do
        return :already_applied if InventoryAction.exists?(idempotency_key: @idempotency_key)

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

        before = snapshot(balance)

        InventoryAction.create!(
          sku: @sku,
          action_type: "stock_in",
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        StockMovement.create!(
          sku: @sku,
          delta_on_hand: @quantity,
          reason: "stock_in",
          meta: @meta
        )

        balance.update!(on_hand: balance.on_hand + @quantity)
        after = snapshot(balance)
        result = :stocked_in
      end

      unfreeze_result = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "stock_in", meta: @meta)
      resolve_result = Inventory::ResolveOversellIncidents.call!(sku: @sku, trigger: "stock_in", meta: @meta)

      Rails.logger.info(
        {
          event: "inventory.stock_in.done",
          sku: @sku.code,
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta,
          result: result,
          unfreeze_result: unfreeze_result,
          resolve_oversell_result: resolve_result,
          before: before,
          after: after
        }.compact.to_json
      )

      result
    rescue ActiveRecord::RecordNotUnique
      :already_applied
    end

    private

    def snapshot(b)
      {
        on_hand: b.on_hand,
        reserved: b.reserved,
        frozen_at: b.frozen_at,
        freeze_reason: b.freeze_reason,
        raw_available: b.raw_available,
        store_available: b.store_available,
        online_available_if_unfrozen: b.online_available(buffer_quantity: @sku.buffer_quantity)
      }
    end
  end
end

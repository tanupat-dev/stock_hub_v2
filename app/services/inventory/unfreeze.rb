# frozen_string_literal: true

module Inventory
  class Unfreeze
    def self.call!(sku:, idempotency_key:, meta: {})
      new(sku:, idempotency_key:, meta:).call!
    end

    def initialize(sku:, idempotency_key:, meta:)
      @sku = sku
      @idempotency_key = idempotency_key.to_s
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "sku is required" if @sku.nil?
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      result = nil
      before = nil
      after = nil

      InventoryBalance.transaction do
        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)
        before = snapshot(balance)

        if !balance.frozen_now?
          result = :not_frozen
        else
          balance.update!(
            frozen_at: nil,
            freeze_reason: nil
          )
          result = :unfrozen
        end

        after = snapshot(balance.reload)
      end

      StockSync::RequestDebouncer.call!(
        sku: @sku,
        reason: "manual_unfreeze"
      )

      Rails.logger.info(
        {
          event: "inventory.unfreeze",
          sku_id: @sku.id,
          sku: @sku.code,
          idempotency_key: @idempotency_key,
          meta: @meta,
          result: result,
          before: before,
          after: after
        }.compact.to_json
      )

      result
    end

    private

    def snapshot(balance)
      {
        on_hand: balance.on_hand,
        reserved: balance.reserved,
        frozen_at: balance.frozen_at,
        freeze_reason: balance.freeze_reason,
        raw_available: balance.raw_available,
        store_available: balance.store_available,
        online_available_if_unfrozen: balance.online_available(buffer_quantity: @sku.buffer_quantity)
      }
    end
  end
end

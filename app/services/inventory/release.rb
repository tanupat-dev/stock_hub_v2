# frozen_string_literal: true

module Inventory
  class Release
    def self.call!(sku:, quantity:, idempotency_key:, meta: {}, order_line: nil)
      new(sku:, quantity:, idempotency_key:, meta:, order_line:).call!
    end

    def initialize(sku:, quantity:, idempotency_key:, meta:, order_line:)
      @sku = sku
      @quantity = Integer(quantity)
      @idempotency_key = idempotency_key
      @meta = meta || {}
      @order_line = order_line
    end

    def call!
      raise ArgumentError, "quantity must be > 0" if @quantity <= 0

      result = nil
      before = nil
      after = nil

      InventoryAction.transaction do
        result = :already_applied and break if InventoryAction.exists?(idempotency_key: @idempotency_key)

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)
        before = snapshot(balance)

        if balance.reserved.to_i <= 0
          after = snapshot(balance)
          result = :noop_no_reserved_stock
          break
        end

        new_reserved = balance.reserved - @quantity
        new_reserved = 0 if new_reserved < 0

        InventoryAction.create!(
          sku: @sku,
          order_line: @order_line,
          action_type: "release",
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        balance.update!(reserved: new_reserved)
        after = snapshot(balance)
        result = :released
      end

      unfreeze_result = nil
      resolve_result = nil

      if result == :released
        unfreeze_result = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "release", meta: @meta)
        resolve_result = Inventory::ResolveOversellIncidents.call!(sku: @sku, trigger: "release", meta: @meta)

        Rails.logger.info(
          {
            event: "inventory.release.done",
            sku: @sku.code,
            order_line_id: @order_line&.id,
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
      else
        Rails.logger.info(
          {
            event: "inventory.release.skip",
            sku: @sku.code,
            order_line_id: @order_line&.id,
            quantity: @quantity,
            idempotency_key: @idempotency_key,
            meta: @meta,
            result: result,
            before: before,
            after: after
          }.compact.to_json
        )
      end

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

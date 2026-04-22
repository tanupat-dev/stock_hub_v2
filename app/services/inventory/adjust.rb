# frozen_string_literal: true

module Inventory
  class Adjust
    def self.call!(sku:, delta: nil, set_to: nil, idempotency_key:, meta: {})
      new(sku:, delta:, set_to:, idempotency_key:, meta:).call!
    end

    def initialize(sku:, delta:, set_to:, idempotency_key:, meta:)
      @sku = sku
      @delta = delta&.to_i
      @set_to = set_to&.to_i
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "sku is required" if @sku.nil?
      raise ArgumentError, "provide either delta or set_to" if @delta.nil? && @set_to.nil?

      before = nil
      after = nil
      result = nil
      shortfall = 0
      possible_oversell = false

      InventoryAction.transaction do
        return :already_applied if InventoryAction.exists?(idempotency_key: @idempotency_key)

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

        before = snapshot(balance)

        target_on_hand =
          if !@set_to.nil?
            @set_to
          else
            balance.on_hand + @delta
          end

        target_on_hand = 0 if target_on_hand < 0

        if target_on_hand == balance.on_hand
          Rails.logger.info(
            {
              event: "inventory.stock_adjust.noop",
              sku: @sku.code,
              idempotency_key: @idempotency_key,
              reason: "same_on_hand"
            }.to_json
          )
          return :already_applied
        end

        possible_oversell = target_on_hand < balance.reserved.to_i
        shortfall = [ balance.reserved.to_i - target_on_hand, 0 ].max

        balance.update!(on_hand: target_on_hand)

        delta_effective = target_on_hand - before[:on_hand]

        InventoryAction.create!(
          sku: @sku,
          action_type: "stock_adjust",
          quantity: delta_effective.abs,
          idempotency_key: @idempotency_key,
          meta: @meta.merge(
            shortfall: shortfall,
            adjust_mode: !@set_to.nil? ? "set_to" : "delta"
          )
        )

        StockMovement.create!(
          sku: @sku,
          delta_on_hand: delta_effective,
          reason: "stock_adjust",
          meta: @meta.merge(
            shortfall: shortfall,
            adjust_mode: !@set_to.nil? ? "set_to" : "delta"
          )
        )

        after = snapshot(balance)
        result = :adjusted
      end

      oversell_result = nil
      unfreeze_result = nil
      resolve_result = nil

      if possible_oversell
        oversell_result = Inventory::OversellGuard.call!(
          sku: @sku,
          trigger: "stock_adjust",
          idempotency_key: "oversell:stock_adjust:sku=#{@sku.id}:request=#{@idempotency_key}",
          meta: @meta.merge(
            source: "stock_adjust",
            stock_adjust_idempotency_key: @idempotency_key,
            shortfall: shortfall
          )
        )
      else
        unfreeze_result = Inventory::UnfreezeIfResolved.call!(
          sku: @sku,
          trigger: "stock_adjust",
          meta: @meta
        )

        resolve_result = Inventory::ResolveOversellIncidents.call!(
          sku: @sku,
          trigger: "stock_adjust",
          meta: @meta
        )
      end

      Rails.logger.info(
        {
          event: "inventory.stock_adjust.done",
          sku: @sku.code,
          idempotency_key: @idempotency_key,
          result: result,
          shortfall: shortfall,
          oversell_result: oversell_result,
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

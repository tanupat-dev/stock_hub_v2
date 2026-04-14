# frozen_string_literal: true

module Inventory
  class Reserve
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

      InventoryAction.transaction do
        return :already_applied if InventoryAction.exists?(idempotency_key: @idempotency_key)

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

        before = snapshot(balance)

        # ✅ If frozen: marketplace reserve blocked (POS is not using reserve)
        if balance.frozen_now?
          log_info(event: "inventory.reserve.blocked", result: :frozen, before: before, after: before)
          return :frozen
        end

        # ✅ Single source of truth: balance primitive (no duplicated formula)
        online_available_now = balance.online_available(buffer_quantity: @sku.buffer_quantity)

        if online_available_now < @quantity
          balance.update!(frozen_at: Time.current, freeze_reason: "not_enough_stock")
          after = snapshot(balance)

          log_info(
            event: "inventory.reserve.blocked",
            result: :not_enough_stock,
            online_available_now: online_available_now,
            before: before,
            after: after
          )
          return :not_enough_stock
        end

        InventoryAction.create!(
          sku: @sku,
          order_line: @order_line,
          action_type: "reserve",
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        balance.update!(reserved: balance.reserved + @quantity)
        after = snapshot(balance)

        log_info(
          event: "inventory.reserve.done",
          result: :reserved,
          online_available_now: online_available_now,
          before: before,
          after: after
        )

        :reserved
      end
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

    def log_info(payload)
      Rails.logger.info(
        {
          event: payload[:event],
          sku: @sku.code,
          order_line_id: @order_line&.id,
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta,
          result: payload[:result],
          online_available_now: payload[:online_available_now],
          before: payload[:before],
          after: payload[:after]
        }.compact.to_json
      )
    end
  end
end

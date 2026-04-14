# frozen_string_literal: true

module Inventory
  class Commit
    class OnHandWouldGoNegative < StandardError; end

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

        # ✅ POS must be able to commit even while frozen, so we only LOG it (do not block)
        if balance.frozen_now?
          Rails.logger.info(
            {
              event: "inventory.commit.while_frozen",
              sku: @sku.code,
              order_line_id: @order_line&.id,
              quantity: @quantity,
              idempotency_key: @idempotency_key,
              meta: @meta,
              before: before
            }.compact.to_json
          )
        end

        new_on_hand = balance.on_hand - @quantity
        new_reserved = balance.reserved - @quantity
        new_reserved = 0 if new_reserved < 0

        raise OnHandWouldGoNegative, "on_hand would be negative for sku=#{@sku.code}" if new_on_hand < 0

        InventoryAction.create!(
          sku: @sku,
          order_line: @order_line,
          action_type: "commit",
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        balance.update!(on_hand: new_on_hand, reserved: new_reserved)
        after = snapshot(balance)

        Rails.logger.info(
          {
            event: "inventory.commit.done",
            sku: @sku.code,
            order_line_id: @order_line&.id,
            quantity: @quantity,
            idempotency_key: @idempotency_key,
            meta: @meta,
            result: :committed,
            before: before,
            after: after
          }.compact.to_json
        )

        :committed
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
  end
end

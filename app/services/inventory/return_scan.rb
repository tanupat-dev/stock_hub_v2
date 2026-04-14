# frozen_string_literal: true

module Inventory
  class ReturnScan
    class ReturnExceedsOrdered < StandardError; end

    def self.call!(return_shipment:, order_line:, quantity:, idempotency_key:, meta: {})
      new(return_shipment:, order_line:, quantity:, idempotency_key:, meta:).call!
    end

    def initialize(return_shipment:, order_line:, quantity:, idempotency_key:, meta:)
      @return_shipment = return_shipment
      @order_line = order_line
      @sku = order_line.sku
      @quantity = Integer(quantity)
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "quantity must be > 0" if @quantity <= 0
      raise ArgumentError, "order_line has no sku" if @sku.nil?

      before = nil
      after = nil
      result = nil

      InventoryAction.transaction do
        return :already_applied if InventoryAction.exists?(idempotency_key: @idempotency_key)

        pending = @order_line.return_pending_qty
        raise ReturnExceedsOrdered, "pending=#{pending} scan=#{@quantity}" if @quantity > pending

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

        before = snapshot(balance)

        ::ReturnScan.create!(
          return_shipment: @return_shipment,
          order_line: @order_line,
          sku: @sku,
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta,
          scanned_at: Time.current
        )

        InventoryAction.create!(
          sku: @sku,
          order_line: @order_line,
          action_type: "return_scan",
          quantity: @quantity,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        ::StockMovement.create!(
          sku: @sku,
          delta_on_hand: @quantity,
          reason: "return_scan",
          meta: @meta.merge(return_shipment_id: @return_shipment.id, order_line_id: @order_line.id)
        )

        balance.update!(on_hand: balance.on_hand + @quantity)
        after = snapshot(balance)
        result = :returned
      end

      unfreeze_result = Inventory::UnfreezeIfResolved.call!(sku: @sku, trigger: "return_scan", meta: @meta)
      resolve_result = Inventory::ResolveOversellIncidents.call!(sku: @sku, trigger: "return_scan", meta: @meta)

      Rails.logger.info(
        {
          event: "inventory.return_scan.done",
          sku: @sku.code,
          order_line_id: @order_line.id,
          return_shipment_id: @return_shipment.id,
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

# frozen_string_literal: true

module Inventory
  class ManualUnfreeze
    def self.call!(sku:, meta: {})
      new(sku:, meta:).call!
    end

    def initialize(sku:, meta:)
      @sku = sku
      @meta = meta || {}
    end

    def call!
      b = @sku.inventory_balance
      return log_and_return(:no_balance) unless b

      result = nil
      before = nil
      after = nil

      InventoryBalance.transaction do
        b.lock!

        before = snapshot(b)

        unless b.frozen_now?
          result = :not_frozen
          next
        end

        unless b.freeze_reason == "manual"
          result = :not_manual
          next
        end

        b.update!(frozen_at: nil, freeze_reason: nil)
        result = :manual_unfrozen
        after = snapshot(b)
      end

      Rails.logger.info(
        {
          event: "inventory.manual_unfreeze",
          sku: @sku.code,
          result: result,
          meta: @meta,
          before: before,
          after: after
        }.compact.to_json
      )

      result
    end

    private

    def snapshot(b)
      {
        on_hand: b.on_hand,
        reserved: b.reserved,
        frozen_at: b.frozen_at,
        freeze_reason: b.freeze_reason
      }
    end

    def log_and_return(res)
      Rails.logger.info(
        {
          event: "inventory.manual_unfreeze",
          sku: @sku.code,
          result: res,
          meta: @meta
        }.to_json
      )
      res
    end
  end
end
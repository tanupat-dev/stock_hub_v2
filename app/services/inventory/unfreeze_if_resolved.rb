# frozen_string_literal: true

module Inventory
  class UnfreezeIfResolved
    def self.call!(sku:, trigger: nil, meta: {})
      new(sku:, trigger:, meta:).call!
    end

    def initialize(sku:, trigger:, meta:)
      @sku = sku
      @trigger = trigger
      @meta = meta || {}
    end

    def call!
      b = @sku.inventory_balance
      return log_and_return(:no_balance) unless b
      return log_and_return(:not_frozen) unless b.frozen_now?

      # ✅ manual freeze ต้องปลดเองเท่านั้น
      return log_and_return(:manual_freeze) if b.freeze_reason == "manual"

      result = nil
      before = nil
      after = nil
      online_raw = nil

      b.with_lock do
        unless b.frozen_now?
          result = :not_frozen
          next
        end

        if b.freeze_reason == "manual"
          result = :manual_freeze
          next
        end

        before = snapshot(b)

        # ✅ IMPORTANT: use RAW (no clamp) for policy
        online_raw = b.online_available_raw(buffer_quantity: @sku.buffer_quantity)

        # ✅ POLICY: safe when raw_available - buffer >= 0
        if online_raw >= 0
          b.update!(frozen_at: nil, freeze_reason: nil)
          result = :unfrozen
        else
          result = :still_problematic
        end

        after = snapshot(b)
      end

      Rails.logger.info(
        {
          event: "inventory.unfreeze_if_resolved",
          sku: @sku.code,
          trigger: @trigger,
          result: result,
          meta: @meta,
          raw_available: b.raw_available,
          store_available: b.store_available,
          online_available_raw_if_unfrozen: online_raw,
          online_available_if_unfrozen: b.online_available(buffer_quantity: @sku.buffer_quantity),
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
          event: "inventory.unfreeze_if_resolved",
          sku: @sku.code,
          trigger: @trigger,
          result: res,
          meta: @meta
        }.to_json
      )
      res
    end
  end
end
# frozen_string_literal: true

module Inventory
  class SystemFreeze
    def self.call!(sku:, reason:, meta: {})
      new(sku:, reason:, meta:).call!
    end

    def initialize(sku:, reason:, meta:)
      @sku = sku
      @reason = reason.to_s.strip.presence || "system"
      @meta = meta || {}
    end

    def call!
      b = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

      before = nil
      after = nil

      InventoryBalance.transaction do
        b.lock!

        before = snapshot(b)

        # ✅ system freeze: set freeze_reason to reason (NOT "manual")
        # ถ้า frozen อยู่แล้ว ก็ update reason ให้เป็นเหตุผลล่าสุดได้ (keep frozen_at as now for trace)
        b.update!(
          frozen_at: Time.current,
          freeze_reason: @reason
        )

        after = snapshot(b)
      end

      Rails.logger.info(
        {
          event: "inventory.system_freeze",
          sku: @sku.code,
          reason: @reason,
          meta: @meta,
          before: before,
          after: after
        }.to_json
      )

      :system_frozen
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
  end
end

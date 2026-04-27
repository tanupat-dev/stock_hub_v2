# frozen_string_literal: true

module Inventory
  class ManualFreeze
    def self.call!(sku:, reason: nil, meta: {})
      new(sku:, reason:, meta:).call!
    end

    def initialize(sku:, reason:, meta:)
      @sku = sku
      @reason = reason
      @meta = meta || {}
    end

    def call!
      b = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

      before = nil
      after = nil

      InventoryBalance.transaction do
        b.lock!

        before = snapshot(b)

        b.update!(
          frozen_at: Time.current,
          freeze_reason: "manual"
        )

        after = snapshot(b)
      end

      Rails.logger.info(
        {
          event: "inventory.manual_freeze",
          sku: @sku.code,
          reason: @reason,
          meta: @meta,
          before: before,
          after: after
        }.to_json
      )

      :manual_frozen
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
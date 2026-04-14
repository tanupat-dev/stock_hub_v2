# frozen_string_literal: true

module Inventory
  class OversellAllocator
    def self.call!(sku:, shortfall_qty:)
      new(sku:, shortfall_qty:).call!
    end

    def initialize(sku:, shortfall_qty:)
      @sku = sku
      @shortfall_qty = shortfall_qty.to_i
    end

    def call!
      return [] if @shortfall_qty <= 0

      rows = InventoryAction
        .where(sku_id: @sku.id)
        .where.not(order_line_id: nil)
        .where(action_type: %w[reserve release commit])
        .select(
          "order_line_id,
           MIN(CASE WHEN action_type='reserve' THEN created_at END) AS first_reserved_at,
           SUM(CASE WHEN action_type='reserve' THEN quantity ELSE 0 END) AS sum_reserve,
           SUM(CASE WHEN action_type='release' THEN quantity ELSE 0 END) AS sum_release,
           SUM(CASE WHEN action_type='commit' THEN quantity ELSE 0 END) AS sum_commit"
        )
        .group("order_line_id")
        .having(
          "SUM(CASE WHEN action_type='reserve' THEN quantity ELSE 0 END)
           - SUM(CASE WHEN action_type='release' THEN quantity ELSE 0 END)
           - SUM(CASE WHEN action_type='commit' THEN quantity ELSE 0 END) > 0"
        )
        .order(Arel.sql("first_reserved_at ASC NULLS LAST"))

      remaining = @shortfall_qty
      allocations = []

      rows.each do |r|
        break if remaining <= 0

        outstanding = r.sum_reserve.to_i - r.sum_release.to_i - r.sum_commit.to_i
        next if outstanding <= 0

        take = [outstanding, remaining].min
        allocations << { order_line_id: r.order_line_id, qty: take }
        remaining -= take
      end

      allocations
    end
  end
end
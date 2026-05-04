# frozen_string_literal: true

module Orders
  module OpenReserve
    module_function

    CLOSING_ACTION_TYPES = %w[commit release].freeze

    def exists?(order)
      open_lines(order).any?
    end

    def open_lines(order)
      order.order_lines.includes(:sku).select do |line|
        open_quantity(line).positive?
      end
    end

    def open_quantity(line)
      reserved = quantity_for(line, "reserve")
      closed = quantity_for(line, CLOSING_ACTION_TYPES)

      reserved - closed
    end

    def quantity_for(line, action_types)
      InventoryAction
        .where(order_line_id: line.id, action_type: action_types)
        .sum(:quantity)
        .to_i
    end

    def commit_safe?(order)
      open_lines(order).all? do |line|
        qty = open_quantity(line)
        next true if qty <= 0

        sku = line.sku
        next false if sku.nil?

        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: sku)
        balance.on_hand.to_i >= qty
      end
    end

    def summary(order)
      open_lines(order).map do |line|
        sku = line.sku
        balance = sku.present? ? Inventory::BalanceFetcher.fetch_for_update!(sku: sku) : nil

        {
          order_line_id: line.id,
          sku_id: sku&.id,
          sku: sku&.code,
          stock_identity_id: sku&.stock_identity_id,
          open_quantity: open_quantity(line),
          balance_on_hand: balance&.on_hand,
          balance_reserved: balance&.reserved,
          balance_frozen_at: balance&.frozen_at,
          balance_freeze_reason: balance&.freeze_reason
        }
      end
    end
  end
end

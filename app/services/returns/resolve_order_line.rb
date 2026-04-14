# frozen_string_literal: true

module Returns
  class ResolveOrderLine
    def self.call(order:, existing_order_line:, sku_code:, requested_qty:)
      new(
        order: order,
        existing_order_line: existing_order_line,
        sku_code: sku_code,
        requested_qty: requested_qty
      ).call
    end

    def initialize(order:, existing_order_line:, sku_code:, requested_qty:)
      @order = order
      @existing_order_line = existing_order_line
      @sku_code = sku_code.to_s.strip
      @requested_qty = requested_qty.to_i
    end

    def call
      return @existing_order_line if @existing_order_line.present?
      return nil if @order.nil?
      return nil if @sku_code.blank?

      candidates = candidate_lines
      return nil if candidates.empty?

      exact_qty = candidates.find { |line| line.quantity.to_i == normalized_requested_qty }
      return exact_qty if exact_qty.present?

      enough_qty = candidates.find { |line| line.quantity.to_i >= normalized_requested_qty }
      return enough_qty if enough_qty.present?

      candidates.first
    end

    private

    def normalized_requested_qty
      @requested_qty.positive? ? @requested_qty : 1
    end

    def candidate_lines
      @order
        .order_lines
        .includes(:sku)
        .select { |line| line.sku&.code.to_s.strip == @sku_code }
        .sort_by(&:id)
    end
  end
end

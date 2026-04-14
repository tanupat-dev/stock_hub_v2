# frozen_string_literal: true

module PackingExports
  class SummaryBuilder
    def self.call(orders:)
      new(orders: orders).call
    end

    def initialize(orders:)
      @orders = Array(orders)
    end

    def call
      {
        all: build_for_scope(@orders),
        by_channel: build_by_channel
      }
    end

    private

    def build_by_channel
      @orders.group_by(&:channel).transform_values do |orders|
        build_for_scope(orders)
      end
    end

    def build_for_scope(orders)
      result = Hash.new(0)

      orders.each do |order|
        order.order_lines.each do |line|
          key = line.sku&.code || line.external_sku
          next if key.blank?

          result[key] += line.quantity.to_i
        end
      end

      result.sort_by { |sku, _| sku }
    end
  end
end

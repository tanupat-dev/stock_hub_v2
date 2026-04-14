# frozen_string_literal: true

module Inventory
  class RemapSkuReferences
    def self.call!(shop:, channel:, external_skus:)
      new(shop:, channel:, external_skus:).call!
    end

    def initialize(shop:, channel:, external_skus:)
      @shop = shop
      @channel = channel.to_s
      @external_skus = Array(external_skus).map { |v| v.to_s.strip }.reject(&:blank?).uniq
    end

    def call!
      return {
        ok: true,
        shop_id: @shop.id,
        channel: @channel,
        external_skus: [],
        order_lines_remapped: 0,
        return_lines_remapped: 0
      } if @external_skus.blank?

      mappings_by_external_sku = SkuMapping.includes(:sku)
                                           .where(channel: @channel, shop_id: @shop.id, external_sku: @external_skus)
                                           .index_by(&:external_sku)

      order_lines_remapped = remap_order_lines!(mappings_by_external_sku)
      return_lines_remapped = remap_return_lines!(mappings_by_external_sku)

      {
        ok: true,
        shop_id: @shop.id,
        channel: @channel,
        external_skus: @external_skus,
        order_lines_remapped: order_lines_remapped,
        return_lines_remapped: return_lines_remapped
      }
    end

    private

    def remap_order_lines!(mappings_by_external_sku)
      changed = 0

      OrderLine
        .joins(:order)
        .where(orders: { shop_id: @shop.id, channel: @channel })
        .where(external_sku: @external_skus)
        .where(sku_id: nil)
        .find_each do |line|
        sku = mappings_by_external_sku[line.external_sku.to_s]&.sku
        next if sku.nil?

        line.update_columns(
          sku_id: sku.id,
          updated_at: Time.current
        )
        changed += 1
      end

      changed
    end

    def remap_return_lines!(mappings_by_external_sku)
      changed = 0

      ReturnShipment
        .includes(:order, return_shipment_lines: [ :order_line, :sku ])
        .where(shop_id: @shop.id, channel: @channel)
        .find_each do |shipment|
        order = shipment.order
        next if order.nil?

        shipment_changed = false

        shipment.return_shipment_lines.each do |line|
          next if line.sku_id.present? && line.order_line_id.present?

          sku_code = line.sku_code_snapshot.to_s.strip
          next if sku_code.blank?
          next unless @external_skus.include?(sku_code)

          sku = mappings_by_external_sku[sku_code]&.sku || Sku.find_by(code: sku_code)

          order_line = Returns::ResolveOrderLine.call(
            order: order,
            existing_order_line: line.order_line,
            sku_code: sku_code,
            requested_qty: line.qty_returned.to_i
          )

          next if sku.nil? && order_line.nil?

          line.update_columns(
            sku_id: sku&.id || line.sku_id,
            order_line_id: order_line&.id || line.order_line_id,
            updated_at: Time.current
          )

          changed += 1
          shipment_changed = true
        end

        shipment.refresh_status_store! if shipment_changed
      end

      changed
    end
  end
end

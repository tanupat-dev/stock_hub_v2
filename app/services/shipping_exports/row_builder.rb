# app/services/shipping_exports/row_builder.rb
# frozen_string_literal: true

module ShippingExports
  class RowBuilder
    def self.call(orders:, export_date: Date.current)
      new(orders: orders, export_date: export_date).call
    end

    def initialize(orders:, export_date:)
      @orders = Array(orders)
      @export_date = export_date
    end

    def call
      rows = []
      running_sequence = 0

      sorted_orders.each do |order|
        order_rows = build_order_rows(order)
        next if order_rows.empty?

        running_sequence += 1
        order_rows.first[:sequence] = running_sequence
        rows.concat(order_rows)
      end

      rows.each_with_index do |row, idx|
        row[:row_index] = idx + 1
      end

      rows.sort_by! do |r|
        [
          r[:shop_code].to_s,
          r[:ordered_at].to_i,
          r[:order_id].to_i,
          r[:row_index].to_i
        ]
      end

      rows
    end

    private

    attr_reader :orders, :export_date

    def sorted_orders
      orders.sort_by do |order|
        [
          shop_sort_key(order.shop),
          ordered_at_sort_key(order),
          order.id
        ]
      end
    end

    def build_order_rows(order)
      rows = []
      ordered_at = ordered_at_sort_key(order)

      order.order_lines.sort_by(&:id).each do |line|
        qty = line.quantity.to_i
        next if qty <= 0

        sku_code = line.sku&.code.to_s.presence || line.external_sku.to_s.strip
        next if sku_code.blank?

        parsed = split_sku_code(sku_code)

        qty.times do
          rows << {
            sequence: nil,
            export_date: export_date,
            order_number: order.external_order_id,
            brand: parsed[:brand],
            model: parsed[:model],
            color: parsed[:color],
            size: parsed[:size],
            item_name: sku_code,
            quantity: 1,
            buyer_name: nil,
            province: nil,
            requisition_bill: nil,
            detail: nil,
            price: nil,
            shop: nil,
            channel: order.channel,
            shop_code: order.shop&.shop_code,
            order_id: order.id,
            ordered_at: ordered_at
          }
        end
      end

      return [] if rows.empty?

      rows.first[:buyer_name] = order.buyer_name.to_s.presence
      rows.first[:province] = order.province.to_s.presence
      rows.first[:detail] = buyer_detail(order)
      rows.first[:shop] = export_shop_label(order.shop)

      rows
    end

    def split_sku_code(sku_code)
      parts = sku_code.to_s.split(".", 4).map { |v| v.to_s.strip }

      {
        brand: parts[0].presence,
        model: parts[1].presence,
        color: parts[2].presence,
        size: parts[3].presence
      }
    end

    def buyer_detail(order)
      payload = order.raw_payload || {}

      detail =
        case order.channel.to_s
        when "tiktok"
          payload["buyer_message"].presence || order.buyer_note.presence
        when "lazada"
          payload["buyer_note"].presence ||
            payload["remarks"].presence ||
            order.buyer_note.presence
        when "shopee"
          payload["message_to_seller"].presence || order.buyer_note.presence
        else
          order.buyer_note.presence
        end

      detail.to_s.presence
    end

    def ordered_at_sort_key(order)
      payload = order.raw_payload || {}

      case order.channel.to_s
      when "tiktok"
        ts = payload["create_time"].to_i
        return ts if ts.positive?
      when "lazada"
        return Time.parse(payload["created_at"].to_s).to_i if payload["created_at"].present?
      when "shopee"
        return payload["ordered_at_ts"].to_i if payload["ordered_at_ts"].to_i.positive?
      end

      (order.updated_at_external || order.created_at).to_i
    rescue
      (order.updated_at_external || order.created_at).to_i
    end

    def shop_sort_key(shop)
      shop&.shop_code.to_s
    end

    def export_shop_label(shop)
      return nil if shop.nil?

      code = shop.shop_code.to_s.strip
      code_downcase = code.downcase
      name = shop.name.to_s.strip

      # TikTok
      return "TikTok 1" if code == "THLCJ4W23M"
      return "TikTok 2" if code == "THLCM7WX8H"

      return "TikTok 1" if code_downcase == "tiktok_1"
      return "TikTok 2" if code_downcase == "tiktok_2"

      return "TikTok 1" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 1").zero?
      return "TikTok 2" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 2").zero?

      return "TikTok 1" if name.casecmp("Thailumlongshop II").zero?
      return "TikTok 2" if name.casecmp("Young smile shoes").zero?

      # Lazada
      return "Lazada 1" if code == "THJ2HAHL"
      return "Lazada 2" if code == "TH1JHM87NL"

      return "Lazada 1" if code_downcase == "lazada_1"
      return "Lazada 2" if code_downcase == "lazada_2"

      return "Lazada 1" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 1").zero?
      return "Lazada 2" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 2").zero?

      return "Lazada 1" if name.casecmp("Thai Lumlong Shop").zero?
      return "Lazada 2" if name.casecmp("Thai Lumlong Shop II").zero?
      return "Lazada 1" if name.casecmp("Lazada 1").zero?
      return "Lazada 2" if name.casecmp("Lazada 2").zero?

      # Shopee / POS
      return "Shopee" if code_downcase.start_with?("shopee")
      return "Shopee" if name.downcase.start_with?("shopee")
      return "POS" if code_downcase == "pos" || code_downcase.start_with?("pos")

      name.presence || code
    end
  end
end

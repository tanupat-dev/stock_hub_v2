# app/controllers/ops/orders_controller.rb
# frozen_string_literal: true

module Ops
  class OrdersController < ApplicationController
    skip_forgery_protection only: :export_shipping_sheet

    def index
      limit = normalized_limit

      online_orders = filtered_online_orders(limit: limit)
      pos_orders = filtered_pos_sales(limit: limit)

      rows = [
        *online_orders.map { |order| serialize_online_order(order) },
        *pos_orders.map { |sale| serialize_pos_sale(sale) }
      ]

      rows = rows
        .sort_by { |row| row[:ordered_at] || "" }
        .reverse
        .first(limit)

      render json: {
        ok: true,
        filters: current_filters.merge(limit: limit),
        count: rows.size,
        orders: rows
      }
    rescue Date::Error
      render json: { ok: false, error: "invalid date" }, status: :bad_request
    end

    def export_shipping_sheet
      batch = ShippingExports::CreateBatch.call!(
        filters: export_filters,
        export_key: params[:export_key],
        export_date: Date.current
      )

      unless batch.file_path.present? && File.exist?(batch.file_path)
        return render json: {
          ok: false,
          error: "file_not_found",
          message: "export file was not generated"
        }, status: :unprocessable_entity
      end

      send_file(
        batch.file_path,
        filename: File.basename(batch.file_path),
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        disposition: "attachment"
      )
    rescue Date::Error
      render json: { ok: false, error: "invalid date" }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "ops.orders.export_shipping_sheet.failed",
          err_class: e.class.name,
          err_message: e.message,
          filters: export_filters
        }.to_json
      )

      render json: {
        ok: false,
        error: e.class.name,
        message: e.message
      }, status: :unprocessable_entity
    end

    def export_packing_sheet
      orders = ShippingExports::OrderScope.call(filters: export_filters).to_a

      summary = PackingExports::SummaryBuilder.call(orders: orders)

      path = Rails.root.join("tmp", "exports", "packing", "packing_#{Time.now.to_i}.xlsx")

      PackingExports::XlsxGenerator.call(
        summary: summary,
        output_path: path,
        export_date: Date.current
      )

      send_file(
        path,
        filename: "packing_list.xlsx",
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        disposition: "attachment"
      )
    rescue Date::Error
      render json: { ok: false, error: "invalid date" }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "ops.orders.export_packing_sheet.failed",
          err_class: e.class.name,
          err_message: e.message,
          filters: export_filters
        }.to_json
      )

      render json: {
        ok: false,
        error: e.class.name,
        message: e.message
      }, status: :unprocessable_entity
    end

    private

    def filtered_online_orders(limit:)
      scope = Order.includes(:shop, order_lines: :sku).order(updated_at_external: :desc, id: :desc)

      if params[:status].present?
        normalized_status = normalize_order_status_filter(params[:status])
        scope = scope.where(status: normalized_status) if normalized_status.present?
      end

      if params[:shop].present?
        normalized_shop_codes = normalize_shop_filter(params[:shop])
        return Order.none if normalized_shop_codes.empty?

        scope = scope.joins(:shop).where(shops: { shop_code: normalized_shop_codes })
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from].to_s)
        scope = scope.where("COALESCE(updated_at_external, created_at) >= ?", from.beginning_of_day)
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to].to_s)
        scope = scope.where("COALESCE(updated_at_external, created_at) <= ?", to.end_of_day)
      end

      if params[:q].present?
        q = "%#{sanitize_sql_like(params[:q].to_s.strip)}%"
        scope = scope.left_joins(:order_lines).where(
          <<~SQL.squish,
            orders.external_order_id ILIKE :q
            OR order_lines.external_sku ILIKE :q
          SQL
          q: q
        ).distinct
      end

      scope.limit(limit)
    end

    def filtered_pos_sales(limit:)
      scope = PosSale.includes(:shop, pos_sale_lines: :sku).order(created_at: :desc, id: :desc)

      if params[:status].present?
        return PosSale.none
      end

      if params[:shop].present?
        normalized_shop_codes = normalize_shop_filter(params[:shop])
        return PosSale.none if normalized_shop_codes.empty?

        scope = scope.joins(:shop).where(shops: { shop_code: normalized_shop_codes })
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from].to_s)
        scope = scope.where("COALESCE(checked_out_at, created_at) >= ?", from.beginning_of_day)
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to].to_s)
        scope = scope.where("COALESCE(checked_out_at, created_at) <= ?", to.end_of_day)
      end

      if params[:q].present?
        q = "%#{sanitize_sql_like(params[:q].to_s.strip)}%"
        scope = scope.left_joins(:pos_sale_lines).where(
          <<~SQL.squish,
            pos_sales.sale_number ILIKE :q
            OR pos_sale_lines.sku_code_snapshot ILIKE :q
            OR pos_sale_lines.barcode_snapshot ILIKE :q
          SQL
          q: q
        ).distinct
      end

      scope.limit(limit)
    end

    def serialize_online_order(order)
      {
        source_type: "online_order",
        id: order.id,
        order_number: order.external_order_id,
        display_order_number: order.external_order_id,
        amount: extract_online_amount(order),
        channel: order.channel,
        display_channel: channel_label(order.channel),
        shop: order.shop&.shop_code,
        display_shop: shop_label(order.shop),
        status: order.status,
        logistic_provider: extract_online_logistic(order),
        tracking_number: extract_online_tracking_number(order),
        buyer_message: extract_online_buyer_message(order),
        ordered_at: extract_online_ordered_at(order),
        lines: order.order_lines.sort_by(&:id).map do |line|
          {
            sku_code: line.sku&.code || line.external_sku,
            quantity: line.quantity
          }
        end
      }
    end

    def serialize_pos_sale(sale)
      {
        source_type: "pos_sale",
        id: sale.id,
        order_number: sale.sale_number,
        display_order_number: "POS",
        amount: nil,
        channel: "pos",
        display_channel: "POS",
        shop: sale.shop&.shop_code,
        display_shop: shop_label(sale.shop),
        status: sale.status,
        logistic_provider: nil,
        tracking_number: nil,
        buyer_message: nil,
        ordered_at: (sale.checked_out_at || sale.created_at)&.iso8601,
        lines: sale.pos_sale_lines.sort_by(&:id).map do |line|
          {
            sku_code: line.sku_code_snapshot,
            quantity: line.quantity
          }
        end
      }
    end

    def extract_online_logistic(order)
      payload = order.raw_payload || {}

      case order.channel.to_s
      when "tiktok"
        payload["shipping_provider"].presence ||
          payload["delivery_option_name"].presence ||
          Array(payload["line_items"]).first&.dig("shipping_provider_name").presence
      when "lazada"
        payload["delivery_info"].presence ||
          Array(payload["line_items"]).first&.dig("shipment_provider").presence
      when "shopee"
        payload["shipping_carrier"].presence ||
          payload["logistics_channel"].presence
      else
        nil
      end
    end

    def extract_online_tracking_number(order)
      payload = order.raw_payload || {}

      case order.channel.to_s
      when "tiktok"
        payload["tracking_number"].presence ||
          Array(payload["line_items"]).first&.dig("tracking_number").presence
      when "lazada"
        payload["tracking_number"].presence ||
          payload["tracking_code"].presence ||
          Array(payload["line_items"]).first&.dig("tracking_number").presence ||
          Array(payload["line_items"]).first&.dig("tracking_code").presence
      when "shopee"
        payload["tracking_no"].presence ||
          payload["tracking_number"].presence
      else
        nil
      end
    end

    def extract_online_buyer_message(order)
      payload = order.raw_payload || {}

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
    end

    def extract_online_amount(order)
      payload = order.raw_payload || {}

      case order.channel.to_s
      when "tiktok"
        payload.dig("payment", "total_amount").presence
      when "lazada"
        payload["amount"].presence || payload["price"].presence
      when "shopee"
        payload["order_amount"].presence ||
          payload["total_amount"].presence
      else
        nil
      end
    end

    def extract_online_ordered_at(order)
      payload = order.raw_payload || {}

      case order.channel.to_s
      when "tiktok"
        ts = payload["create_time"].to_i
        return Time.at(ts).iso8601 if ts.positive?
      when "lazada"
        return payload["created_at"] if payload["created_at"].present?
      when "shopee"
        return payload["create_time"] if payload["create_time"].present?
      end

      (order.updated_at_external || order.created_at)&.iso8601
    end

    def channel_label(channel)
      case channel.to_s
      when "tiktok" then "TikTok"
      when "lazada" then "Lazada"
      when "shopee" then "Shopee"
      when "pos" then "POS"
      else channel.to_s.titleize
      end
    end

    def shop_label(shop)
      Shop.display_label_for(shop)
    end

    def normalize_shop_filter(value)
      Shop.normalize_filter_codes(value)
    end

    def normalize_order_status_filter(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      case raw.downcase
      when "pending"
        "PENDING"
      when "awaiting_fulfillment"
        "AWAITING_FULFILLMENT"
      when "ready_to_ship"
        "READY_TO_SHIP"
      when "awaiting_shipment"
        "AWAITING_FULFILLMENT"
      when "awaiting_collection"
        "READY_TO_SHIP"
      when "in_transit"
        "IN_TRANSIT"
      when "cancelled"
        "CANCELLED"
      when "delivered"
        "DELIVERED"
      when "completed"
        "COMPLETED"
      else
        raw.upcase
      end
    end

    def normalized_limit
      raw = params[:limit].to_i
      return 50 if raw <= 0
      return 200 if raw > 200

      raw
    end

    def current_filters
      {
        q: params[:q].presence,
        status: params[:status].presence,
        shop: params[:shop].presence,
        date_from: params[:date_from].presence,
        date_to: params[:date_to].presence
      }.compact
    end

    def export_filters
      {
        q: params[:q].presence,
        shop: params[:shop].presence,
        date_from: params[:date_from].presence,
        date_to: params[:date_to].presence,
        status: params[:status].presence
      }.compact
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end
  end
end

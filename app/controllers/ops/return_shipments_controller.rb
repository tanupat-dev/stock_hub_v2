# app/controllers/ops/return_shipments_controller.rb
# frozen_string_literal: true

module Ops
  class ReturnShipmentsController < BaseController
    def index
      @active_ops_nav = :orders

      scope = ReturnShipment
                .includes(:shop, :order, :return_scans, :return_shipment_lines)
                .order(updated_at: :desc, id: :desc)

      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"

        scope = scope.where(
          "external_return_id ILIKE :q OR external_order_id ILIKE :q OR tracking_number ILIKE :q",
          q: q
        )
      end

      if params[:channel].present?
        scope = scope.where(channel: params[:channel].to_s.strip)
      end

      if params[:shop_group].present?
        shop_ids = shop_ids_for_group(params[:shop_group])
        scope = shop_ids.any? ? scope.where(shop_id: shop_ids) : scope.none
      elsif params[:shop_id].present?
        scope = scope.where(shop_id: params[:shop_id].to_i)
      end

      if params[:status_store].present?
        scope = scope.where(status_store: params[:status_store].to_s.strip)
      end

      if params[:status_marketplace].present?
        scope = scope.where(status_marketplace: params[:status_marketplace].to_s.strip)
      end

      if params[:external_return_id].present?
        scope = scope.where(external_return_id: params[:external_return_id].to_s.strip)
      end

      if params[:external_order_id].present?
        scope = scope.where(external_order_id: params[:external_order_id].to_s.strip)
      end

      limit = normalize_limit(params[:limit])
      shipments = scope.limit(limit).to_a

      render json: {
        ok: true,
        count: shipments.size,
        filters: {
          q: params[:q],
          channel: params[:channel],
          shop_id: params[:shop_id],
          shop_group: params[:shop_group],
          status_store: params[:status_store],
          status_marketplace: params[:status_marketplace],
          external_return_id: params[:external_return_id],
          external_order_id: params[:external_order_id],
          limit: limit
        },
        return_shipments: shipments.map { |shipment| serialize_shipment(shipment) }
      }
    rescue => e
      Rails.logger.error(
        {
          event: "ops.return_shipments.index.failed",
          err_class: e.class.name,
          err_message: e.message,
          params: params.to_unsafe_h.slice(
            "q",
            "channel",
            "shop_id",
            "shop_group",
            "status_store",
            "status_marketplace",
            "external_return_id",
            "external_order_id",
            "limit"
          )
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def show
      shipment = ReturnShipment
                   .includes(:shop, :order, { return_shipment_lines: [ :sku, :order_line ] }, :return_scans)
                   .find(params[:id])

      render json: {
        ok: true,
        return_shipment: serialize_shipment_detail(shipment)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue => e
      Rails.logger.error(
        {
          event: "ops.return_shipments.show.failed",
          err_class: e.class.name,
          err_message: e.message,
          id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def normalize_limit(raw)
      value = raw.to_i
      return 50 if value <= 0
      return 200 if value > 200

      value
    end

    def serialize_shipment(shipment)
      returned_scan_at = latest_return_scan_at(shipment)

      {
        id: shipment.id,
        channel: shipment.channel,
        shop_id: shipment.shop_id,
        shop_code: shipment.shop&.shop_code,
        shop_label: human_shop_label(shipment.shop),
        order_id: shipment.order_id,
        external_order_id: shipment.external_order_id,
        external_return_id: shipment.external_return_id,
        tracking_number: shipment.tracking_number,
        buyer_username: shipment.buyer_username,
        status_store: shipment.status_store,
        derived_status_store: shipment.derived_status_store,
        status_marketplace: shipment.status_marketplace,
        requested_at: shipment.requested_at,
        return_carrier_method: shipment.return_carrier_method,
        return_delivery_status: shipment.return_delivery_status,

        # Marketplace delivered/received timestamp. Keep it for audit/debug only.
        # Do not use this as the store returned date in the UI.
        returned_delivered_at: shipment.returned_delivered_at,

        # Actual in-store returned timestamp from barcode scanning.
        returned_at: returned_scan_at,
        returned_scan_at: returned_scan_at,

        total_qty_requested: shipment.total_qty_requested,
        total_qty_scanned: shipment.total_qty_scanned,
        line_count: shipment.return_shipment_lines.size,
        last_seen_at_external: shipment.last_seen_at_external,
        created_at: shipment.created_at,
        updated_at: shipment.updated_at
      }
    end

    def serialize_shipment_detail(shipment)
      serialize_shipment(shipment).merge(
        order: shipment.order && {
          id: shipment.order.id,
          channel: shipment.order.channel,
          shop_id: shipment.order.shop_id,
          external_order_id: shipment.order.external_order_id,
          status: shipment.order.status
        },
        lines: shipment.return_shipment_lines.sort_by(&:id).map do |line|
          {
            id: line.id,
            order_line_id: line.order_line_id,
            sku_id: line.sku_id,
            sku_code_snapshot: line.sku_code_snapshot,
            sku_code: line.sku&.code,
            barcode: line.sku&.barcode,
            qty_returned: line.qty_returned,
            scanned_qty: line.scanned_qty,
            pending_scan_qty: line.pending_scan_qty,
            fully_scanned: line.fully_scanned?
          }
        end,
        scans: shipment.return_scans.order(:id).map do |scan|
          {
            id: scan.id,
            order_line_id: scan.order_line_id,
            sku_id: scan.sku_id,
            quantity: scan.quantity,
            scanned_at: scan.scanned_at,
            idempotency_key: scan.idempotency_key
          }
        end
      )
    end

    def latest_return_scan_at(shipment)
      if shipment.association(:return_scans).loaded?
        shipment.return_scans.map(&:scanned_at).compact.max
      else
        shipment.return_scans.maximum(:scanned_at)
      end
    end

    def shop_ids_for_group(group_key)
      shops = Shop.where(channel: %w[tiktok lazada shopee]).to_a

      shops.select { |shop| shop_group_key(shop) == group_key.to_s.strip }
           .map(&:id)
    end

    def shop_group_key(shop)
      label = human_shop_label(shop)

      case label
      when "Lazada 1" then "lazada_1"
      when "Lazada 2" then "lazada_2"
      when "TikTok 1" then "tiktok_1"
      when "TikTok 2" then "tiktok_2"
      when "Shopee 1", "Shopee" then "shopee_1"
      else
        shop.shop_code.to_s
      end
    end

    def human_shop_label(shop)
      return "-" if shop.nil?

      code = shop.shop_code.to_s
      name = shop.name.to_s

      return "Lazada 1" if code.include?("thj2hahl")
      return "Lazada 2" if code.include?("th1jhm87nl")

      return "TikTok 1" if code.include?("7468184483922740997") || code == "THLCJ4W23M"
      return "TikTok 2" if code.include?("7469737153154172677") || code == "THLCM7WX8H"

      return "Shopee" if code.start_with?("shopee")

      name.presence || code
    end
  end
end

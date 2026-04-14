# frozen_string_literal: true

module Pos
  class ReturnsController < BaseController
    class ShipmentLineExceedsRequested < StandardError; end

    # POST /pos/returns/lookup
    def lookup
      rs = find_return_shipment!

      shipment_lines = rs.return_shipment_lines.includes(:sku, :order_line).order(:id).to_a
      status_store = rs.derived_status_store

      lines = shipment_lines.map do |line|
        serialize_shipment_line(line)
      end

      log_pos_info(
        event: "pos.returns.lookup",
        lookup: safe_lookup_params,
        return_shipment_id: rs.id,
        order_id: rs.order_id
      )

      render json: {
        ok: true,
        return_shipment: serialize_return_shipment(rs, derived_status_store: status_store),
        order: rs.order ? serialize_order(rs.order) : nil,
        summary: {
          line_count: lines.size,
          total_qty_requested: lines.sum { |line| line[:qty_requested].to_i },
          total_qty_returned: lines.sum { |line| line[:qty_scanned].to_i },
          total_qty_pending: lines.sum { |line| line[:qty_pending].to_i }
        },
        return_lines: lines
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    end

    # POST /pos/returns/scan
    def scan
      rs = ReturnShipment.includes(return_shipment_lines: [ :sku, :order_line ]).find(params.require(:return_shipment_id))
      scan_input = params.require(:barcode).to_s.strip
      raise ArgumentError, "barcode must be present" if scan_input.blank?

      sku, matched_by = find_sku_for_scan!(scan_input)
      quantity = params.fetch(:quantity, 1).to_i
      raise ArgumentError, "quantity must be > 0" if quantity <= 0

      shipment_line = find_shipment_line_for_scan!(rs: rs, sku: sku)

      line = shipment_line.order_line
      if line.nil?
        return render json: { ok: false, error: "order_line not mapped for this return line" }, status: :unprocessable_entity
      end

      if line.order_id != rs.order_id
        return render json: { ok: false, error: "order_line does not belong to this return_shipment" }, status: :unprocessable_entity
      end

      if line.sku_id.present? && line.sku_id != sku.id
        return render json: { ok: false, error: "SKU mismatch for this order_line" }, status: :unprocessable_entity
      end

      if quantity > shipment_line.pending_scan_qty
        raise ShipmentLineExceedsRequested,
              "shipment_line_pending=#{shipment_line.pending_scan_qty} scan=#{quantity}"
      end

      before = sku_snapshot(sku)

      res = Inventory::ReturnScan.call!(
        return_shipment: rs,
        order_line: line,
        quantity: quantity,
        idempotency_key: params.require(:idempotency_key),
        meta: {
          source: "pos",
          raw: params.to_unsafe_h,
          return_shipment_line_id: shipment_line.id,
          scan_input: scan_input,
          scan_match_type: matched_by
        }
      )

      rs.reload
      shipment_line.reload
      status_store = rs.refresh_status_store!
      after = sku_snapshot(sku)

      log_pos_info(
        event: "pos.returns.scan",
        return_shipment_id: rs.id,
        return_shipment_line_id: shipment_line.id,
        order_line_id: line.id,
        sku: sku.code,
        barcode: sku.barcode,
        scan_input: scan_input,
        scan_match_type: matched_by,
        quantity: quantity,
        idempotency_key: params[:idempotency_key].to_s,
        result: res,
        return_shipment_status_store: status_store,
        before: before,
        after: after
      )

      render json: {
        ok: true,
        result: res,
        return_shipment: serialize_return_shipment(rs.reload, derived_status_store: status_store),
        return_line: serialize_shipment_line(shipment_line.reload),
        idempotency_key: params[:idempotency_key],
        sku: { id: sku.id, code: sku.code, barcode: sku.barcode },
        scan_input: scan_input,
        scan_match_type: matched_by,
        before: before,
        after: after
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue Inventory::ReturnScan::ReturnExceedsOrdered => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ShipmentLineExceedsRequested => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :bad_request
    end

    private

    def find_return_shipment!
      if params[:tracking_number].present?
        ReturnShipment.find_by!(tracking_number: params[:tracking_number])
      elsif params[:external_return_id].present?
        ReturnShipment.find_by!(
          channel: params.require(:channel),
          shop_id: params.require(:shop_id),
          external_return_id: params[:external_return_id]
        )
      else
        ReturnShipment.find_by!(
          channel: params.require(:channel),
          shop_id: params.require(:shop_id),
          external_order_id: params.require(:external_order_id)
        )
      end
    end

    def find_sku_for_scan!(scan_input)
      sku = Sku.find_by(barcode: scan_input)
      return [ sku, "barcode" ] if sku.present?

      sku = Sku.find_by(code: scan_input)
      return [ sku, "sku_code" ] if sku.present?

      raise ActiveRecord::RecordNotFound, "sku not found for scan input"
    end

    def find_shipment_line_for_scan!(rs:, sku:)
      shipment_lines = rs.return_shipment_lines.to_a

      exact = shipment_lines.find { |line| line.sku_id.present? && line.sku_id == sku.id && line.pending_scan_qty.positive? }
      return exact if exact.present?

      by_code = shipment_lines.find do |line|
        line.sku_id.blank? &&
          line.sku_code_snapshot.to_s.strip == sku.code.to_s.strip &&
          line.pending_scan_qty.positive?
      end
      return by_code if by_code.present?

      raise ActiveRecord::RecordNotFound, "return shipment line not found for scan input"
    end

    def safe_lookup_params
      params.to_unsafe_h.slice("tracking_number", "external_return_id", "external_order_id", "shop_id", "channel")
    end

    def serialize_return_shipment(rs, derived_status_store:)
      {
        id: rs.id,
        channel: rs.channel,
        shop_id: rs.shop_id,
        order_id: rs.order_id,
        external_order_id: rs.external_order_id,
        external_return_id: rs.external_return_id,
        tracking_number: rs.tracking_number,
        status_store: rs.status_store,
        derived_status_store: derived_status_store,
        status_marketplace: rs.status_marketplace,
        requested_at: rs.requested_at,
        return_carrier_method: rs.return_carrier_method,
        return_delivery_status: rs.return_delivery_status,
        returned_delivered_at: rs.returned_delivered_at,
        buyer_username: rs.buyer_username,
        last_seen_at_external: rs.last_seen_at_external,
        scanned_any: rs.scanned_any?,
        fully_scanned: rs.fully_scanned?,
        total_qty_requested: rs.total_qty_requested,
        total_qty_scanned: rs.total_qty_scanned
      }
    end

    def serialize_order(order)
      {
        id: order.id,
        channel: order.channel,
        shop_id: order.shop_id,
        external_order_id: order.external_order_id,
        status: order.status,
        buyer_name: order.buyer_name,
        province: order.province
      }
    end

    def serialize_shipment_line(line)
      order_line = line.order_line
      sku = line.sku || order_line&.sku

      {
        id: line.id,
        return_shipment_id: line.return_shipment_id,
        order_line_id: line.order_line_id,
        sku_id: sku&.id,
        sku_code: sku&.code || line.sku_code_snapshot,
        barcode: sku&.barcode,
        qty_requested: line.qty_returned,
        qty_scanned: line.scanned_qty,
        qty_pending: line.pending_scan_qty,
        fully_scanned: line.fully_scanned?,
        order_line_quantity: order_line&.quantity,
        order_line_returned_qty: order_line&.returned_qty,
        order_line_pending_qty: order_line&.return_pending_qty
      }
    end
  end
end

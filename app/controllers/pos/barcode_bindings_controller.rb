# frozen_string_literal: true

module Pos
  class BarcodeBindingsController < BaseController
    def create
      sku =
        if params[:sku_id].present?
          Sku.find(params[:sku_id])
        elsif params[:sku_code].present?
          Sku.find_by!(code: params[:sku_code].to_s.strip)
        else
          return render json: { ok: false, error: "sku_id or sku_code required" }, status: :bad_request
        end

      barcode = params[:barcode].to_s
      force = ActiveModel::Type::Boolean.new.cast(params[:force])

      before = sku_snapshot(sku)

      result = Inventory::BindBarcode.call!(
        sku: sku,
        barcode: barcode,
        force: force,
        meta: {
          source: "pos_barcode_binding",
          request_id: request.request_id
        }
      )

      after = sku_snapshot(sku.reload)

      log_pos_info(
        event: "pos.barcode_binding",
        sku_id: sku.id,
        sku: sku.code,
        barcode: barcode.to_s.gsub(/\s+/, "").strip,
        force: force,
        result: result,
        before: before,
        after: after
      )

      render json: {
        ok: true,
        result: result,
        sku: {
          id: sku.id,
          code: sku.code,
          barcode: sku.barcode
        },
        before: before,
        after: after
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue Inventory::BindBarcode::SkuRequired,
           Inventory::BindBarcode::BarcodeBlank => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue Inventory::BindBarcode::BarcodeAlreadyAssigned,
           Inventory::BindBarcode::BarcodeAlreadyBoundOnSku => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end
  end
end

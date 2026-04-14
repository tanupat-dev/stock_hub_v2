# frozen_string_literal: true

module Ops
  class BarcodeBindingsController < BaseController
    def index
      @active_ops_nav = :barcode_bindings
    end

    def import
      file = params.require(:file)
      force = ActiveModel::Type::Boolean.new.cast(params[:force])

      result = BarcodeBindings::ImportCsv.call!(file: file, force: force)

      render json: {
        ok: true,
        result: result
      }
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error(
        {
          event: "ops.barcode_bindings.import.failed",
          error_class: e.class.name,
          error: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def clear
      sku =
        if params[:sku_id].present?
          Sku.find(params[:sku_id])
        elsif params[:sku_code].present?
          Sku.find_by!(code: params[:sku_code].to_s.strip)
        else
          return render json: { ok: false, error: "sku_id or sku_code required" }, status: :bad_request
        end

      before = snapshot_sku(sku)

      result = Inventory::ClearBarcode.call!(
        sku: sku,
        meta: {
          source: "ops_barcode_binding_clear",
          request_id: request.request_id
        }
      )

      after = snapshot_sku(sku.reload)

      Rails.logger.info(
        {
          event: "ops.barcode_bindings.clear",
          request_id: request.request_id,
          sku_id: sku.id,
          sku: sku.code,
          result: result,
          before: before,
          after: after
        }.to_json
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
    rescue Inventory::ClearBarcode::SkuRequired => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error(
        {
          event: "ops.barcode_bindings.clear.failed",
          request_id: request.request_id,
          error_class: e.class.name,
          error: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def snapshot_sku(sku)
      {
        id: sku.id,
        code: sku.code,
        barcode: sku.barcode
      }
    end
  end
end

# frozen_string_literal: true

module Ops
  class ProductsController < BaseController
    def index
      @active_ops_nav = :products
    end

    def export_skus
      skus = Sku
        .where(active: true)
        .includes(:inventory_balance)
        .order(:code)

      path = Rails.root.join("tmp", "exports", "skus", "skus_#{Time.now.to_i}.xlsx")
      FileUtils.mkdir_p(File.dirname(path))

      SkuExports::XlsxGenerator.call(
        skus: skus,
        output_path: path
      )

      send_file(
        path,
        filename: "sku_master_with_stock.xlsx",
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        disposition: "attachment"
      )
    end

    def archive
      sku = Sku.find(params[:id])

      sku.update!(
        active: false,
        archived_at: Time.current
      )

      Rails.logger.info(
        {
          event: "ops.products.archive",
          sku_id: sku.id,
          sku_code: sku.code,
          request_id: request.request_id
        }.to_json
      )

      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def unarchive
      sku = Sku.find(params[:id])

      sku.update!(
        active: true,
        archived_at: nil
      )

      Rails.logger.info(
        {
          event: "ops.products.unarchive",
          sku_id: sku.id,
          sku_code: sku.code,
          request_id: request.request_id
        }.to_json
      )

      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end
  end
end

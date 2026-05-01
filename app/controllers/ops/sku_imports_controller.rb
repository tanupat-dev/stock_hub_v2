# frozen_string_literal: true

require "csv"

module Ops
  class SkuImportsController < BaseController
    MAX_ROWS = 10_000

    def create
      file = params.require(:file)

      rows = parse_csv(file)

      if rows.size > MAX_ROWS
        return render json: {
          ok: false,
          error: "File too large (max #{MAX_ROWS} rows)"
        }, status: :unprocessable_entity
      end

      batch = SkuImportBatch.create!(
        status: "pending",
        stock_mode: params[:stock_mode].to_s.presence || "skip",
        dry_run: params[:dry_run].to_s == "true",
        original_filename: file.original_filename,
        total_rows: rows.size
      )

      # 🚀 ส่ง DATA เข้า job แทน file
      SkuImportJob.perform_later(batch.id, rows)

      render json: {
        ok: true,
        batch_id: batch.id
      }
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue => e
      Rails.logger.error(
        {
          event: "ops.sku_import.enqueue_failed",
          error_class: e.class.name,
          error: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :internal_server_error
    end

    private

    def parse_csv(file)
      CSV.read(file.path, headers: true, encoding: "bom|utf-8").map(&:to_h)
    end
  end
end

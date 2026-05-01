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

    def show
      batch = SkuImportBatch.find(params[:id])

      render json: {
        ok: true,
        batch: batch.attributes.slice(
          "id",
          "status",
          "dry_run",
          "stock_mode",
          "original_filename",
          "total_rows",
          "upsert_rows",
          "stock_updated",
          "stock_failed",
          "result",
          "error_message",
          "started_at",
          "completed_at",
          "created_at",
          "updated_at"
        )
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Import batch not found" }, status: :not_found
    end

    private

    def parse_csv(file)
      CSV.read(file.path, headers: true, encoding: "bom|utf-8").map(&:to_h)
    end
  end
end

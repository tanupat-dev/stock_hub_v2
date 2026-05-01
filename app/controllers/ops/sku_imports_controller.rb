# frozen_string_literal: true

module Ops
  class SkuImportsController < ApplicationController
    skip_forgery_protection

    def create
      file = params.require(:file)

      batch = SkuImportBatch.create!(
        status: "pending",
        stock_mode: params[:stock_mode].to_s.presence || "skip",
        dry_run: params[:dry_run].to_s == "true",
        original_filename: file.original_filename
      )

      batch.file.attach(file)

      SkuImportJob.perform_later(batch.id)

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

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end
  end
end

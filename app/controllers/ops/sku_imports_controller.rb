# frozen_string_literal: true

module Ops
  class SkuImportsController < ApplicationController
    skip_forgery_protection

    def create
      file = params.require(:file)

      result = SkuImports::ImportCsv.call!(
        file: file,
        dry_run: params[:dry_run].to_s == "true",
        stock_mode: params[:stock_mode].to_s.presence || "skip"
      )

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
          event: "ops.sku_import.failed",
          error_class: e.class.name,
          error: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end
  end
end

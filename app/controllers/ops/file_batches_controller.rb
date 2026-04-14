# frozen_string_literal: true

module Ops
  class FileBatchesController < BaseController
    def index
      @active_ops_nav = :shopee

      scope = FileBatch.includes(:shop).order(created_at: :desc, id: :desc)

      if params[:channel].present?
        scope = scope.where(channel: params[:channel].to_s.strip)
      end

      if params[:kind].present?
        scope = scope.where(kind: params[:kind].to_s.strip)
      end

      if params[:shop_id].present?
        scope = scope.where(shop_id: params[:shop_id].to_i)
      end

      limit = normalize_limit(params[:limit])
      batches = scope.limit(limit).to_a

      render json: {
        ok: true,
        count: batches.size,
        filters: {
          channel: params[:channel],
          kind: params[:kind],
          shop_id: params[:shop_id],
          limit: limit
        },
        file_batches: batches.map do |batch|
          {
            id: batch.id,
            channel: batch.channel,
            shop_id: batch.shop_id,
            shop_code: batch.shop&.shop_code,
            kind: batch.kind,
            status: batch.status,
            source_filename: batch.source_filename,
            total_rows: batch.total_rows,
            success_rows: batch.success_rows,
            failed_rows: batch.failed_rows,
            started_at: batch.started_at,
            finished_at: batch.finished_at,
            error_summary: batch.error_summary,
            meta: batch.meta,
            created_at: batch.created_at,
            updated_at: batch.updated_at
          }
        end
      }
    end

    private

    def normalize_limit(raw)
      value = raw.to_i
      return 50 if value <= 0
      return 200 if value > 200

      value
    end
  end
end

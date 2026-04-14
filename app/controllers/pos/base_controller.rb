# frozen_string_literal: true

module Pos
  class BaseController < ApplicationController
    protect_from_forgery with: :null_session
    before_action :require_pos_key!

    private

    # ===== Production-safe POS auth =====
    def require_pos_key!
      expected = Rails.application.credentials.dig(:pos, :key).to_s
      provided = request.headers["X-POS-KEY"].to_s

      ok = expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      return if ok

      render json: { ok: false, error: "Unauthorized" }, status: :unauthorized
    end

    # ===== Standard envelope helpers =====
    def request_context
      {
        request_id: request.request_id,
        ip: request.remote_ip,
        method: request.request_method,
        path: request.fullpath
      }
    end

    def log_pos_info(event:, **payload)
      Rails.logger.info({ event: event, **request_context, **payload }.to_json)
    end

    def log_pos_error(event:, **payload)
      Rails.logger.error({ event: event, **request_context, **payload }.to_json)
    end

    def sku_snapshot(sku)
      b = sku.inventory_balance&.reload

      {
        sku: {
          id: sku.id,
          code: sku.code,
          barcode: sku.barcode,
          buffer_quantity: sku.buffer_quantity
        },
        balance: b ? {
          on_hand: b.on_hand,
          reserved: b.reserved,
          frozen_at: b.frozen_at,
          freeze_reason: b.freeze_reason,
          last_pushed_available: b.last_pushed_available,
          last_pushed_at: b.last_pushed_at
        } : nil,
        store_available: sku.store_available,
        online_available: sku.online_available
      }
    end
  end
end

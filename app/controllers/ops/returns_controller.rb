# frozen_string_literal: true

module Ops
  class ReturnsController < BaseController
    def index
      @active_ops_nav = :returns
    end

    def shops
      shops = Shop.where(channel: %w[tiktok lazada shopee])
                  .order(:channel, :shop_code)

      render json: {
        ok: true,
        shops: shops.map do |s|
          {
            id: s.id,
            shop_code: s.shop_code,
            channel: s.channel
          }
        end
      }
    rescue => e
      Rails.logger.error(
        {
          event: "ops.returns.shops.failed",
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end
  end
end

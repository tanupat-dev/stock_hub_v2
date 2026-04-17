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
            channel: s.channel,
            label: human_shop_label(s) # ✅ NEW
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

    private

    def human_shop_label(shop)
      code = shop.shop_code.to_s

      # Lazada
      return "Lazada 1" if code.include?("thj2hahl")
      return "Lazada 2" if code.include?("th1jhm87nl")

      # TikTok
      return "TikTok 1" if code.include?("7468184483922740997") || code == "THLCJ4W23M"
      return "TikTok 2" if code.include?("7469737153154172677") || code == "THLCM7WX8H"

      # fallback
      shop.name.presence || shop.shop_code
    end
  end
end

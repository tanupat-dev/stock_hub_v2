# frozen_string_literal: true

module Ops
  class ReturnsController < BaseController
    def index
      @active_ops_nav = :returns
    end

    # 🔥 NEW: dynamic shop list
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
    end
  end
end

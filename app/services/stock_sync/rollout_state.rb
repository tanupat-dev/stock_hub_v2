# frozen_string_literal: true

module StockSync
  class RolloutState
    def self.call
      new.call
    end

    def call
      {
        global_enabled: StockSync::Rollout.global_enabled?,
        prefix_mode: StockSync::Rollout.prefix_mode,
        rollout_prefixes: StockSync::Rollout.prefixes,
        shops: serialize_shops
      }
    end

    private

    def serialize_shops
      Shop.order(:channel, :shop_code).map do |shop|
        {
          id: shop.id,
          channel: shop.channel,
          shop_code: shop.shop_code,
          active: shop.active,
          stock_sync_enabled: shop.stock_sync_enabled,
          sync_fail_count: shop.sync_fail_count.to_i,
          last_sync_failed_at: shop.last_sync_failed_at,
          last_sync_error: shop.last_sync_error
        }
      end
    end
  end
end

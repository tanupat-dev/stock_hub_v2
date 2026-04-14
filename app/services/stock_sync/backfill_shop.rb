# frozen_string_literal: true

module StockSync
  class BackfillShop
    def self.call!(shop:, force: true, reason: "shop_rollout_backfill")
      new(shop:, force:, reason:).call!
    end

    def initialize(shop:, force:, reason:)
      @shop = shop
      @force = force
      @reason = reason
    end

    def call!
      raise ArgumentError, "shop is required" if @shop.nil?

      sku_ids = SkuMapping.where(shop_id: @shop.id).distinct.pluck(:sku_id).compact
      stats = {
        scanned: 0,
        pushed: 0,
        skipped_missing_sku: 0
      }

      sku_ids.each do |sku_id|
        stats[:scanned] += 1

        sku = Sku.find_by(id: sku_id)
        if sku.nil?
          stats[:skipped_missing_sku] += 1
          next
        end

        StockSync::PushSku.call!(
          sku: sku,
          reason: @reason,
          force: @force
        )

        stats[:pushed] += 1
      end

      Rails.logger.info(
        {
          event: "stock_sync.backfill_shop.done",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          channel: @shop.channel,
          force: @force,
          reason: @reason
        }.merge(stats).to_json
      )

      stats
    end
  end
end

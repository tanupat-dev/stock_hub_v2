# frozen_string_literal: true

module StockSync
  class PushSku
    COOLDOWN_WINDOW = 30.minutes

    def self.call!(sku:, reason: nil, force: false)
      new(sku:, reason:, force:).call!
    end

    def initialize(sku:, reason:, force:)
      @sku = sku
      @reason = reason
      @force = force
    end

    def call!
      root_sku = @sku
      available = root_sku.online_available

      skus =
        if root_sku.stock_identity_id.present?
          Sku.where(stock_identity_id: root_sku.stock_identity_id)
        else
          Sku.where(id: root_sku.id)
        end

      Rails.logger.info(
        {
          event: "stock_sync.push_sku_group.start",
          root_sku_id: root_sku.id,
          root_sku: root_sku.code,
          stock_identity_id: root_sku.stock_identity_id,
          group_size: skus.count,
          available: available,
          reason: @reason,
          forced: @force
        }.to_json
      )

      stats = {
        scanned: 0,
        enqueued: 0,
        skipped: 0,
        skipped_pending_duplicate: 0,
        failed: 0
      }

      skus.find_each do |sku|
        SkuMapping
          .where(sku_id: sku.id)
          .joins(:shop)
          .merge(Shop.where(active: true))
          .includes(:shop)
          .find_each do |mapping|
            shop = mapping.shop
            next if shop.nil?

            stats[:scanned] += 1

            result = push_one_shop!(shop, sku, available, mapping)

            case result
            when :enqueued
              stats[:enqueued] += 1
            when :pending_duplicate
              stats[:skipped_pending_duplicate] += 1
            when :failed
              stats[:failed] += 1
            else
              stats[:skipped] += 1
            end
          end
      end

      Rails.logger.info(
        {
          event: "stock_sync.push_sku_group.done",
          root_sku_id: root_sku.id,
          root_sku: root_sku.code,
          stock_identity_id: root_sku.stock_identity_id,
          group_size: skus.count,
          available: available,
          reason: @reason,
          forced: @force
        }.merge(stats).to_json
      )

      available
    end

    private

    def push_one_shop!(shop, sku, available, mapping)
      return :skipped if shop.channel == "tiktok" && shop.tiktok_credential_id.blank?
      return :skipped if shop.channel == "tiktok" && shop.shop_cipher.blank?
      return :skipped if shop.channel == "lazada" && shop.lazada_credential_id.blank?
      return :skipped if shop.channel == "lazada" && shop.lazada_app_id.blank?
      return :skipped if shop.channel == "pos"

      rollout_skip_reason = StockSync::Rollout.skip_reason(shop: shop, sku: sku)
      if rollout_skip_reason.present?
        Rails.logger.info(
          {
            event: "stock_sync.push_marketplace.skip",
            channel: shop.channel,
            shop_code: shop.shop_code,
            shop_id: shop.id,
            sku_id: sku.id,
            sku: sku.code,
            available: available,
            reason: @reason,
            skip_reason: rollout_skip_reason,
            rollout_prefixes: StockSync::Rollout.prefixes,
            shop_stock_sync_enabled: shop.stock_sync_enabled
          }.to_json
        )
        return :skipped
      end

      state = ShopSkuSyncState.find_by(shop_id: shop.id, sku_id: sku.id)

      if !@force && state
        if state.last_pushed_available == available
          skip_reason =
            if state.last_pushed_at.present? && state.last_pushed_at > COOLDOWN_WINDOW.ago
              "cooldown_same_value"
            else
              "no_change"
            end

          Rails.logger.info(
            {
              event: "stock_sync.push_marketplace.skip",
              channel: shop.channel,
              shop_code: shop.shop_code,
              shop_id: shop.id,
              sku_id: sku.id,
              sku: sku.code,
              available: available,
              reason: @reason,
              skip_reason: skip_reason,
              last_pushed_available: state.last_pushed_available,
              last_pushed_at: state.last_pushed_at,
              cooldown_seconds: COOLDOWN_WINDOW.to_i
            }.to_json
          )
          return :skipped
        end
      end

      Rails.logger.info(
        {
          event: "stock_sync.push_marketplace",
          channel: shop.channel,
          shop_code: shop.shop_code,
          shop_id: shop.id,
          sku_id: sku.id,
          sku: sku.code,
          available: available,
          reason: @reason
        }.to_json
      )

      result =
        case shop.channel
        when "tiktok", "lazada"
          enqueue_push_inventory_for_api_marketplace(shop, sku, available, mapping)
        when "shopee"
          :adapter_not_implemented
        else
          :unsupported_channel
        end

      if result != :enqueued
        level = (result == :skipped || result == :pending_duplicate ? :info : :warn)
        Rails.logger.public_send(
          level,
          {
            event: "stock_sync.push_marketplace.skip",
            channel: shop.channel,
            shop_code: shop.shop_code,
            shop_id: shop.id,
            sku_id: sku.id,
            sku: sku.code,
            available: available,
            reason: @reason,
            skip_reason: "not_enqueued",
            result: result
          }.to_json
        )
        return result == :pending_duplicate ? :pending_duplicate : :skipped
      end

      :enqueued
    rescue => e
      Rails.logger.error(
        {
          event: "stock_sync.push_marketplace.fail",
          channel: shop.channel,
          shop_code: shop.shop_code,
          shop_id: shop.id,
          sku_id: sku.id,
          sku: sku.code,
          available: available,
          reason: @reason,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      :failed
    end

    def enqueue_push_inventory_for_api_marketplace(shop, sku, available, mapping)
      variant_id = mapping.external_variant_id.to_s.strip
      raise "missing external_variant_id for SkuMapping id=#{mapping.id}" if variant_id.blank?

      item = MarketplaceItem.find_by(shop_id: shop.id, external_variant_id: variant_id)
      raise "missing MarketplaceItem for variant_id=#{variant_id} shop_id=#{shop.id}" if item.nil?

      unless item.status.to_s.strip.upcase == "ACTIVATE"
        Rails.logger.info(
          {
            event: "stock_sync.push_marketplace.skip",
            channel: shop.channel,
            shop_code: shop.shop_code,
            shop_id: shop.id,
            sku_id: sku.id,
            sku: sku.code,
            available: available,
            reason: @reason,
            skip_reason: "marketplace_item_not_activate",
            marketplace_item_id: item.id,
            status: item.status
          }.to_json
        )
        return :skipped
      end

      if pending_push_inventory_job?(item.id)
        Rails.logger.info(
          {
            event: "stock_sync.push_marketplace.skip",
            channel: shop.channel,
            shop_code: shop.shop_code,
            shop_id: shop.id,
            sku_id: sku.id,
            sku: sku.code,
            marketplace_item_id: item.id,
            available: available,
            reason: @reason,
            skip_reason: "pending_push_inventory_job"
          }.to_json
        )
        return :pending_duplicate
      end

      PushInventoryJob.perform_later(
        shop.id,
        item.id,
        available,
        reason: @reason.presence || "stock_sync.push_sku"
      )

      :enqueued
    end

    def pending_push_inventory_job?(marketplace_item_id)
      SolidQueue::Job
        .where(class_name: "PushInventoryJob", finished_at: nil)
        .where("arguments::text LIKE ?", "%#{marketplace_item_id}%")
        .exists?
    rescue => e
      Rails.logger.warn(
        {
          event: "stock_sync.pending_push_check_failed",
          marketplace_item_id: marketplace_item_id,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      false
    end
  end
end

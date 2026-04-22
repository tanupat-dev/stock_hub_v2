# app/services/inventory/reconcile_shop.rb
# frozen_string_literal: true

module Inventory
  class ReconcileShop
    DEFAULT_FRESH_WITHIN = 6.hours
    DEFAULT_PUSH_LIMIT = 100

    def self.call!(shop:, fresh_within: DEFAULT_FRESH_WITHIN, push_limit: DEFAULT_PUSH_LIMIT)
      new(shop, fresh_within:, push_limit:).call!
    end

    def initialize(shop, fresh_within:, push_limit:)
      @shop = shop
      @fresh_within = fresh_within
      @push_limit = push_limit.to_i <= 0 ? DEFAULT_PUSH_LIMIT : push_limit.to_i

      @scanned_activate = 0
      @mismatched = 0
      @unmapped = 0
      @pushed = 0

      @stale_items = 0
      @stale_mismatched = 0
      @skipped_missing_variant = 0
      @skipped_missing_balance = 0
      @skipped_no_change_state = 0
      @skipped_rollout_blocked = 0
      @skipped_shop_disabled = 0
      @skipped_nil_available_stock = 0
      @skipped_push_limit = 0
    end

    def call!
      unless supported_shop?
        return {
          ok: false,
          shop_id: @shop.id,
          channel: @shop.channel,
          error: "unsupported_or_not_ready_shop"
        }
      end

      cutoff = Time.current - @fresh_within

      mapping_cache = SkuMapping
        .where(channel: @shop.channel, shop_id: @shop.id)
        .includes(:sku)
        .index_by { |m| m.external_variant_id.to_s.strip }

      state_cache = ShopSkuSyncState
        .where(shop_id: @shop.id)
        .index_by(&:sku_id)

      MarketplaceItem
        .where(shop: @shop)
        .where("UPPER(status) = 'ACTIVATE'")
        .find_each do |item|
          @scanned_activate += 1

          item_stale = item.synced_at.blank? || item.synced_at < cutoff
          @stale_items += 1 if item_stale

          if item.available_stock.nil?
            @skipped_nil_available_stock += 1
            next
          end

          variant_id = item.external_variant_id.to_s.strip
          if variant_id.blank?
            @skipped_missing_variant += 1
            @unmapped += 1
            next
          end

          mapping = mapping_cache[variant_id]
          if mapping.nil?
            @unmapped += 1
            next
          end

          sku = mapping.sku
          next if sku.nil?

          if sku.inventory_balance.nil?
            @skipped_missing_balance += 1
            next
          end

          rollout_skip_reason = StockSync::Rollout.skip_reason(shop: @shop, sku: sku)
          if rollout_skip_reason.present?
            case rollout_skip_reason
            when "shop_sync_disabled", "shop_inactive", "global_sync_disabled"
              @skipped_shop_disabled += 1
            when "rollout_prefix_blocked"
              @skipped_rollout_blocked += 1
            end
            next
          end

          central = sku.online_available.to_i
          marketplace = item.available_stock.to_i

          next if central == marketplace

          @mismatched += 1
          @stale_mismatched += 1 if item_stale

          state = state_cache[sku.id]

          if state &&
             state.last_pushed_available.to_i == central &&
             marketplace == central
            @skipped_no_change_state += 1
            next
          end

          if @pushed >= @push_limit
            @skipped_push_limit += 1
            next
          end

          PushInventoryJob.perform_later(
            @shop.id,
            item.id,
            central,
            reason: "reconcile_mismatch"
          )

          @pushed += 1
        end

      InventoryReconcileRun.create!(
        shop: @shop,
        mismatched_count: @mismatched,
        unmapped_count: @unmapped,
        pushed_count: @pushed,
        ran_at: Time.current
      )

      {
        ok: true,
        shop_id: @shop.id,
        channel: @shop.channel,
        fresh_within_seconds: @fresh_within.to_i,
        push_limit: @push_limit,
        scanned_activate: @scanned_activate,
        mismatched: @mismatched,
        unmapped: @unmapped,
        pushed: @pushed,
        stale_items: @stale_items,
        stale_mismatched: @stale_mismatched,
        skipped_missing_variant: @skipped_missing_variant,
        skipped_missing_balance: @skipped_missing_balance,
        skipped_no_change_state: @skipped_no_change_state,
        skipped_rollout_blocked: @skipped_rollout_blocked,
        skipped_shop_disabled: @skipped_shop_disabled,
        skipped_nil_available_stock: @skipped_nil_available_stock,
        skipped_push_limit: @skipped_push_limit
      }
    end

    private

    def supported_shop?
      return false unless @shop.active?

      case @shop.channel
      when "tiktok"
        @shop.tiktok_credential_id.present? && @shop.shop_cipher.present?
      when "lazada"
        @shop.lazada_credential_id.present? && lazada_app_present?
      else
        false
      end
    end

    def lazada_app_present?
      @shop.lazada_app_id.present? || @shop.lazada_credential&.lazada_app.present?
    end
  end
end

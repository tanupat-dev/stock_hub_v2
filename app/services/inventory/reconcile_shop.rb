# frozen_string_literal: true

module Inventory
  class ReconcileShop
    DEFAULT_FRESH_WITHIN = 6.hours
    DEFAULT_PUSH_LIMIT = 100
    BATCH_SIZE = 200

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
      @skipped_pending_duplicate = 0
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

      MarketplaceItem
        .where(shop: @shop)
        .where("UPPER(status) = 'ACTIVATE'")
        .in_batches(of: BATCH_SIZE) do |relation|
          items = relation.to_a
          reconcile_batch!(items, cutoff: cutoff)
        ensure
          items = nil
        end

      InventoryReconcileRun.create!(
        shop: @shop,
        mismatched_count: @mismatched,
        unmapped_count: @unmapped,
        pushed_count: @pushed,
        ran_at: Time.current
      )

      result_payload
    end

    private

    def reconcile_batch!(items, cutoff:)
      variant_ids =
        items
          .map { |item| item.external_variant_id.to_s.strip }
          .reject(&:blank?)
          .uniq

      mappings_by_variant =
        if variant_ids.any?
          SkuMapping
            .where(channel: @shop.channel, shop_id: @shop.id, external_variant_id: variant_ids)
            .includes(sku: :inventory_balance)
            .index_by { |mapping| mapping.external_variant_id.to_s }
        else
          {}
        end

      sku_ids =
        mappings_by_variant
          .values
          .map(&:sku_id)
          .compact
          .uniq

      states_by_sku_id =
        if sku_ids.any?
          ShopSkuSyncState
            .where(shop_id: @shop.id, sku_id: sku_ids)
            .index_by(&:sku_id)
        else
          {}
        end

      items.each do |item|
        reconcile_item!(
          item,
          cutoff: cutoff,
          mappings_by_variant: mappings_by_variant,
          states_by_sku_id: states_by_sku_id
        )
      end
    end

    def reconcile_item!(item, cutoff:, mappings_by_variant:, states_by_sku_id:)
      @scanned_activate += 1

      item_stale = item.synced_at.blank? || item.synced_at < cutoff
      @stale_items += 1 if item_stale

      if item.available_stock.nil?
        @skipped_nil_available_stock += 1
        return
      end

      variant_id = item.external_variant_id.to_s.strip
      if variant_id.blank?
        @skipped_missing_variant += 1
        @unmapped += 1
        return
      end

      mapping = mappings_by_variant[variant_id]
      if mapping.nil?
        @unmapped += 1
        return
      end

      sku = mapping.sku
      return if sku.nil?

      if sku.inventory_balance.nil?
        @skipped_missing_balance += 1
        return
      end

      rollout_skip_reason = StockSync::Rollout.skip_reason(shop: @shop, sku: sku)
      if rollout_skip_reason.present?
        case rollout_skip_reason
        when "shop_sync_disabled", "shop_inactive", "global_sync_disabled"
          @skipped_shop_disabled += 1
        when "rollout_prefix_blocked"
          @skipped_rollout_blocked += 1
        end
        return
      end

      central = sku.online_available.to_i
      marketplace = item.available_stock.to_i

      return if central == marketplace

      @mismatched += 1
      @stale_mismatched += 1 if item_stale

      state = states_by_sku_id[sku.id]

      if state &&
         state.last_pushed_available.to_i == central &&
         marketplace == central
        @skipped_no_change_state += 1
        return
      end

      if @pushed >= @push_limit
        @skipped_push_limit += 1
        return
      end

      if pending_push_inventory_job?(item.id)
        @skipped_pending_duplicate += 1
        return
      end

      PushInventoryJob.perform_later(
        @shop.id,
        item.id,
        central,
        reason: "reconcile_mismatch"
      )

      @pushed += 1
    end

    def pending_push_inventory_job?(marketplace_item_id)
      SolidQueue::Job
        .where(class_name: "PushInventoryJob", finished_at: nil)
        .where("arguments::text LIKE ?", "%#{marketplace_item_id}%")
        .exists?
    rescue => e
      Rails.logger.warn(
        {
          event: "reconcile.pending_push_check_failed",
          marketplace_item_id: marketplace_item_id,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      false
    end

    def result_payload
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
        skipped_push_limit: @skipped_push_limit,
        skipped_pending_duplicate: @skipped_pending_duplicate
      }
    end

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

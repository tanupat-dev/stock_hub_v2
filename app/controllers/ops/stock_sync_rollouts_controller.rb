# frozen_string_literal: true

module Ops
  class StockSyncRolloutsController < BaseController
    skip_before_action :verify_authenticity_token,
      only: [ :update_global, :update_shop, :backfill_shop, :update_prefix_mode, :update_prefix_list ]

    def page
      @active_ops_nav = :stock_sync
      render :page
    end


    def show
      render json: {
        ok: true,
        rollout: StockSync::RolloutState.call
      }
    end

    def update_global
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      StockSync::Rollout.set_global_enabled!(enabled)

      render json: {
        ok: true,
        global_enabled: StockSync::Rollout.global_enabled?
      }
    end

    def update_shop
      shop = Shop.find(params[:id])
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])

      shop.update!(stock_sync_enabled: enabled)

      render json: {
        ok: true,
        shop: {
          id: shop.id,
          channel: shop.channel,
          shop_code: shop.shop_code,
          active: shop.active,
          stock_sync_enabled: shop.stock_sync_enabled
        }
      }
    end

    def backfill_shop
      shop = Shop.find(params[:id])

      result = StockSync::BackfillShop.call!(
        shop: shop,
        force: true,
        reason: "ops_rollout_backfill"
      )

      render json: {
        ok: true,
        result: result
      }
    end

    # ✅ NEW
    def update_prefix_mode
      mode = params[:mode].to_s

      unless %w[all allowlist].include?(mode)
        return render json: { ok: false, error: "invalid_mode" }, status: 422
      end

      SystemSetting.set!(StockSync::Rollout::PREFIX_MODE_KEY, mode)

      render json: {
        ok: true,
        prefix_mode: mode
      }
    end

    def update_prefix_list
      list = params[:prefixes]

      unless list.is_a?(Array)
        return render json: { ok: false, error: "prefixes_must_be_array" }, status: 422
      end

      cleaned = list.map(&:to_s).map(&:strip).reject(&:blank?)

      SystemSetting.set_json!(StockSync::Rollout::PREFIX_LIST_KEY, cleaned)

      render json: {
        ok: true,
        prefixes: cleaned
      }
    end
  end
end

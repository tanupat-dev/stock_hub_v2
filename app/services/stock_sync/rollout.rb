# frozen_string_literal: true

module StockSync
  module Rollout
    module_function

    GLOBAL_KEY = "stock_sync_global_enabled"

    # ✅ NEW
    PREFIX_MODE_KEY = "stock_sync_prefix_mode"
    PREFIX_LIST_KEY = "stock_sync_prefix_allowlist"

    def global_enabled?
      SystemSetting.get_bool(GLOBAL_KEY, default: false)
    rescue StandardError
      false
    end

    def set_global_enabled!(value)
      SystemSetting.set_bool!(GLOBAL_KEY, value)
    end

    # ✅ NEW
    def prefix_mode
      SystemSetting.get(PREFIX_MODE_KEY, default: "allowlist")
    end

    def prefixes
      SystemSetting.get_json(PREFIX_LIST_KEY, default: [])
    end

    def sku_allowed?(sku_code)
      code = sku_code.to_s

      # 🔥 allow all
      return true if prefix_mode == "all"

      # allowlist mode
      return true if prefixes.empty?
      return true if prefixes.include?("*")

      prefixes.any? { |prefix| code.start_with?(prefix) }
    end

    def shop_enabled?(shop)
      return false if shop.nil?
      return false unless shop.active?
      return false unless shop.stock_sync_enabled?

      true
    end

    def allow_push?(shop:, sku:)
      return false unless global_enabled?
      return false unless shop_enabled?(shop)
      return false if sku.nil?
      return false unless sku_allowed?(sku.code)

      true
    end

    def skip_reason(shop:, sku:)
      return "global_sync_disabled" unless global_enabled?
      return "missing_shop" if shop.nil?
      return "shop_inactive" unless shop.active?
      return "shop_sync_disabled" unless shop.stock_sync_enabled?
      return "missing_sku" if sku.nil?
      return "rollout_prefix_blocked" unless sku_allowed?(sku.code)

      nil
    end
  end
end

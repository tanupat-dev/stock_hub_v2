# app/services/stock_sync/rollout_state.rb
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
      Shop.all
          .group_by { |shop| shop_group_key(shop) }
          .values
          .map { |group| serialize_shop_group(group) }
          .sort_by { |row| [ row[:channel].to_s, row[:display_order].to_i, row[:id].to_i ] }
          .map { |row| row.except(:display_order) }
    end

    def serialize_shop_group(group)
      shop = preferred_shop(group)

      {
        id: shop.id,
        channel: shop.channel,
        shop_code: human_shop_label(shop),
        active: group.any?(&:active),
        stock_sync_enabled: group.any?(&:stock_sync_enabled),
        sync_fail_count: group.sum { |s| s.sync_fail_count.to_i },
        last_sync_failed_at: group.map(&:last_sync_failed_at).compact.max,
        last_sync_error: group.map(&:last_sync_error).compact.last,
        display_order: display_order_for(shop)
      }
    end

    def preferred_shop(group)
      group.min_by do |shop|
        [
          shop.active? ? 0 : 1,
          shop.stock_sync_enabled? ? 0 : 1,
          connection_present?(shop) ? 0 : 1,
          shop.id
        ]
      end
    end

    def connection_present?(shop)
      case shop.channel.to_s
      when "tiktok"
        shop.tiktok_app_id.present? || shop.tiktok_credential_id.present?
      when "lazada"
        shop.lazada_app_id.present? || shop.lazada_credential_id.present?
      else
        false
      end
    end

    def display_order_for(shop)
      case human_shop_label(shop)
      when "Lazada 1" then 1
      when "Lazada 2" then 2
      when "POS" then 3
      when "Shopee 1", "Shopee" then 4
      when "TikTok 1" then 5
      when "TikTok 2" then 6
      else 99
      end
    end

    def shop_group_key(shop)
      code = shop.shop_code.to_s
      name = shop.name.to_s
      external_id = shop.external_shop_id.to_s

      return "tiktok_1" if [ code, name, external_id ].any? { |v| tiktok_1_match?(v) }
      return "tiktok_2" if [ code, name, external_id ].any? { |v| tiktok_2_match?(v) }

      return "lazada_1" if [ code, name, external_id ].any? { |v| lazada_1_match?(v) }
      return "lazada_2" if [ code, name, external_id ].any? { |v| lazada_2_match?(v) }

      return "shopee_1" if code.start_with?("shopee") || name.casecmp("Shopee 1").zero?
      return "pos_main" if code.start_with?("pos") || name.casecmp("POS Main").zero?

      code.presence || "#{shop.channel}:#{shop.id}"
    end

    def human_shop_label(shop)
      return "-" if shop.nil?

      case shop_group_key(shop)
      when "tiktok_1" then "TikTok 1"
      when "tiktok_2" then "TikTok 2"
      when "lazada_1" then "Lazada 1"
      when "lazada_2" then "Lazada 2"
      when "shopee_1" then "Shopee 1"
      when "pos_main" then "POS"
      else
        shop.name.presence || shop.shop_code
      end
    end

    def tiktok_1_match?(value)
      str = value.to_s.strip
      str == "7468184483922740997" ||
        str == "THLCJ4W23M" ||
        str.casecmp("Tiktok 1").zero? ||
        str.casecmp("TikTok 1").zero? ||
        str.casecmp("Thailumlongshop II").zero?
    end

    def tiktok_2_match?(value)
      str = value.to_s.strip
      str == "7469737153154172677" ||
        str == "THLCM7WX8H" ||
        str.casecmp("Tiktok 2").zero? ||
        str.casecmp("TikTok 2").zero? ||
        str.casecmp("Young smile shoes").zero?
    end

    def lazada_1_match?(value)
      str = value.to_s.strip
      str.casecmp("THJ2HAHL").zero? ||
        str.casecmp("lazada_shop_thj2hahl").zero? ||
        str.casecmp("Lazada 1").zero? ||
        str.casecmp("Thai Lumlong Shop").zero?
    end

    def lazada_2_match?(value)
      str = value.to_s.strip
      str.casecmp("TH1JHM87NL").zero? ||
        str.casecmp("lazada_shop_th1jhm87nl").zero? ||
        str.casecmp("Lazada 2").zero? ||
        str.casecmp("Thai Lumlong Shop II").zero?
    end
  end
end

# app/services/marketplace_connections/tiktok/prepare_connection.rb
# frozen_string_literal: true

require "securerandom"

module MarketplaceConnections
  module Tiktok
    class PrepareConnection
      def self.call!(shop_name:, external_shop_id:, app_key:, app_secret:)
        new(
          shop_name: shop_name,
          external_shop_id: external_shop_id,
          app_key: app_key,
          app_secret: app_secret
        ).call!
      end

      def initialize(shop_name:, external_shop_id:, app_key:, app_secret:)
        @shop_name = shop_name.to_s.strip.presence
        @external_shop_id = external_shop_id.to_s.strip
        @app_key = app_key.to_s.strip
        @app_secret = app_secret.to_s.strip
      end

      def call!
        raise ArgumentError, "shop_id required" if @external_shop_id.blank?
        raise ArgumentError, "app_key required" if @app_key.blank?
        raise ArgumentError, "app_secret required" if @app_secret.blank?

        Shop.transaction do
          shop = find_existing_shop || Shop.new(channel: "tiktok")

          app = shop.tiktok_app || TiktokApp.new
          app.code ||= generate_app_code
          app.auth_region = app.auth_region.presence || "ROW"
          app.service_id = @external_shop_id
          app.app_key = @app_key
          app.app_secret = @app_secret
          app.open_api_host = app.open_api_host.presence || "https://open-api.tiktokglobalshop.com"
          app.active = true if app.active.nil?
          app.save!

          shop.channel = "tiktok"
          shop.external_shop_id = @external_shop_id if shop.external_shop_id.blank?
          shop.shop_code = shop.shop_code.presence || generate_shop_code(@external_shop_id)
          shop.name = @shop_name if @shop_name.present?
          shop.name = shop.name.presence || default_shop_name
          shop.tiktok_app = app
          shop.active = true if shop.active.nil?
          shop.save!

          { shop: shop, app: app }
        end
      end

      private

      def find_existing_shop
        candidates = Shop.where(channel: "tiktok").to_a

        candidates.find do |shop|
          logical_group_key(shop) == requested_group_key
        end || Shop.find_by(channel: "tiktok", external_shop_id: @external_shop_id)
      end

      def requested_group_key
        return "tiktok_1" if tiktok_1_match?(@external_shop_id) || tiktok_1_match?(@shop_name)
        return "tiktok_2" if tiktok_2_match?(@external_shop_id) || tiktok_2_match?(@shop_name)

        @external_shop_id
      end

      def logical_group_key(shop)
        code = shop.shop_code.to_s
        name = shop.name.to_s
        external_id = shop.external_shop_id.to_s

        return "tiktok_1" if [ code, name, external_id ].any? { |v| tiktok_1_match?(v) }
        return "tiktok_2" if [ code, name, external_id ].any? { |v| tiktok_2_match?(v) }

        external_id.presence || code
      end

      def default_shop_name
        case requested_group_key
        when "tiktok_1" then "TikTok 1"
        when "tiktok_2" then "TikTok 2"
        else "TikTok #{@external_shop_id}"
        end
      end

      def generate_app_code
        "tiktok_app_#{SecureRandom.hex(4)}"
      end

      def generate_shop_code(external_shop_id)
        "tiktok_shop_#{external_shop_id.to_s.parameterize(separator: "_")}"
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
    end
  end
end

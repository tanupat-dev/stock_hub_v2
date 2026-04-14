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
          shop = Shop.find_or_initialize_by(channel: "tiktok", external_shop_id: @external_shop_id)

          app = shop.tiktok_app || TiktokApp.new
          app.code ||= generate_app_code
          app.auth_region = app.auth_region.presence || "ROW"
          app.service_id = @external_shop_id
          app.app_key = @app_key
          app.app_secret = @app_secret
          app.open_api_host = app.open_api_host.presence || "https://open-api.tiktokglobalshop.com"
          app.active = true if app.active.nil?
          app.save!

          shop.shop_code = shop.shop_code.presence || generate_shop_code(@external_shop_id)
          shop.name = @shop_name if @shop_name.present?
          shop.name = shop.name.presence || "TikTok #{@external_shop_id}"
          shop.tiktok_app = app
          shop.active = true if shop.active.nil?
          shop.save!

          { shop: shop, app: app }
        end
      end

      private

      def generate_app_code
        "tiktok_app_#{SecureRandom.hex(4)}"
      end

      def generate_shop_code(external_shop_id)
        "tiktok_shop_#{external_shop_id.to_s.parameterize(separator: "_")}"
      end
    end
  end
end

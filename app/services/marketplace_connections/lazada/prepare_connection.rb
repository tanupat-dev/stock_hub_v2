# frozen_string_literal: true

require "securerandom"

module MarketplaceConnections
  module Lazada
    class PrepareConnection
      def self.call!(shop_name:, seller_input:, app_key:, app_secret:, callback_url:)
        new(
          shop_name: shop_name,
          seller_input: seller_input,
          app_key: app_key,
          app_secret: app_secret,
          callback_url: callback_url
        ).call!
      end

      def initialize(shop_name:, seller_input:, app_key:, app_secret:, callback_url:)
        @shop_name = shop_name.to_s.strip.presence
        @seller_input = seller_input.to_s.strip
        @app_key = app_key.to_s.strip
        @app_secret = app_secret.to_s.strip
        @callback_url = callback_url.to_s.strip
      end

      def call!
        raise ArgumentError, "seller_id required" if @seller_input.blank?
        raise ArgumentError, "app_key required" if @app_key.blank?
        raise ArgumentError, "app_secret required" if @app_secret.blank?

        Shop.transaction do
          shop = Shop.find_or_initialize_by(channel: "lazada", external_shop_id: @seller_input)

          app = shop.lazada_app || LazadaApp.new
          app.code ||= generate_app_code
          app.app_key = @app_key
          app.app_secret = @app_secret
          app.auth_host = app.auth_host.presence || "https://auth.lazada.com"
          app.api_host = app.api_host.presence || "https://api.lazada.co.th"
          app.callback_url = @callback_url
          app.active = true if app.active.nil?
          app.save!

          shop.shop_code = shop.shop_code.presence || generate_shop_code(@seller_input)
          shop.name = @shop_name if @shop_name.present?
          shop.name = shop.name.presence || "Lazada #{@seller_input}"
          shop.lazada_app = app
          shop.active = true if shop.active.nil?
          shop.save!

          { shop: shop, app: app }
        end
      end

      private

      def generate_app_code
        "lazada_app_#{SecureRandom.hex(4)}"
      end

      def generate_shop_code(seller_input)
        "lazada_shop_#{seller_input.to_s.parameterize(separator: "_")}"
      end
    end
  end
end

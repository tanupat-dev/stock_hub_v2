# app/services/marketplace_connections/lazada/prepare_connection.rb
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
          shop = find_existing_shop || Shop.new(channel: "lazada")

          app = shop.lazada_app || LazadaApp.new
          app.code ||= generate_app_code
          app.app_key = @app_key
          app.app_secret = @app_secret
          app.auth_host = app.auth_host.presence || "https://auth.lazada.com"
          app.api_host = app.api_host.presence || "https://api.lazada.co.th"
          app.callback_url = @callback_url
          app.active = true if app.active.nil?
          app.save!

          shop.channel = "lazada"
          shop.external_shop_id = @seller_input if shop.external_shop_id.blank?
          shop.shop_code = shop.shop_code.presence || generate_shop_code(@seller_input)
          shop.name = @shop_name if @shop_name.present?
          shop.name = shop.name.presence || default_shop_name
          shop.lazada_app = app
          shop.active = true if shop.active.nil?
          shop.save!

          { shop: shop, app: app }
        end
      end

      private

      def find_existing_shop
        candidates = Shop.where(channel: "lazada").to_a

        candidates.find do |shop|
          logical_group_key(shop) == requested_group_key
        end || Shop.find_by(channel: "lazada", external_shop_id: @seller_input)
      end

      def requested_group_key
        return "lazada_1" if lazada_1_match?(@seller_input) || lazada_1_match?(@shop_name)
        return "lazada_2" if lazada_2_match?(@seller_input) || lazada_2_match?(@shop_name)

        @seller_input
      end

      def logical_group_key(shop)
        code = shop.shop_code.to_s
        name = shop.name.to_s
        external_id = shop.external_shop_id.to_s

        return "lazada_1" if [ code, name, external_id ].any? { |v| lazada_1_match?(v) }
        return "lazada_2" if [ code, name, external_id ].any? { |v| lazada_2_match?(v) }

        external_id.presence || code
      end

      def default_shop_name
        case requested_group_key
        when "lazada_1" then "Lazada 1"
        when "lazada_2" then "Lazada 2"
        else "Lazada #{@seller_input}"
        end
      end

      def generate_app_code
        "lazada_app_#{SecureRandom.hex(4)}"
      end

      def generate_shop_code(seller_input)
        "lazada_shop_#{seller_input.to_s.parameterize(separator: "_")}"
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
end

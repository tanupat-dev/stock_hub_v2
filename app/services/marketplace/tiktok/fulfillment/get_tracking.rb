# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Fulfillment
      class GetTracking
        def self.call!(shop:, order_id:)
          new(shop:, order_id:).call!
        end

        def initialize(shop:, order_id:)
          @shop = shop
          @order_id = order_id.to_s.strip
        end

        def call!
          raise ArgumentError, "shop required" if @shop.nil?
          raise ArgumentError, "order_id required" if @order_id.blank?
          raise ArgumentError, "shop missing tiktok_credential" if @shop.tiktok_credential.nil?
          raise ArgumentError, "shop_cipher missing" if @shop.shop_cipher.blank?

          client = Marketplace::Tiktok::Client.new(
            credential: @shop.tiktok_credential
          )

          client.get(
            "/fulfillment/202309/orders/#{@order_id}/tracking",
            query: {
              "shop_cipher" => @shop.shop_cipher
            }
          )
        end
      end
    end
  end
end

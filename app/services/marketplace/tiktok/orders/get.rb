# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Orders
      class Get
        def self.call!(shop:, order_id:)
          new(shop).call!(order_id:)
        end

        def initialize(shop)
          raise ArgumentError, "shop missing tiktok_credential" if shop.tiktok_credential.nil?
          raise ArgumentError, "shop_cipher missing" if shop.shop_cipher.blank?

          @shop = shop
          @client = Marketplace::Tiktok::Client.new(
            credential: shop.tiktok_credential
          )
        end

        def call!(order_id:)
          data = @client.get(
            "/order/202309/orders",
            query: {
              "shop_cipher" => @shop.shop_cipher,
              "ids" => order_id.to_s
            }
          )

          Array(data["orders"]).first || {}
        end
      end
    end
  end
end

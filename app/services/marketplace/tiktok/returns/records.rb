# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Returns
      class Records
        def self.call!(shop:, return_id:, locale: "en-US")
          new(shop).call!(return_id: return_id, locale: locale)
        end

        def initialize(shop)
          raise ArgumentError, "shop missing tiktok_credential" if shop.tiktok_credential.nil?
          raise ArgumentError, "shop_cipher missing" if shop.shop_cipher.blank?

          @shop = shop
          @client = Marketplace::Tiktok::Client.new(
            credential: shop.tiktok_credential
          )
        end

        def call!(return_id:, locale: "en-US")
          data = @client.get(
            "/return_refund/202309/returns/#{return_id}/records",
            query: {
              "shop_cipher" => @shop.shop_cipher,
              "locale" => locale
            }
          )

          {
            "records" => Array(data["records"])
          }
        end
      end
    end
  end
end

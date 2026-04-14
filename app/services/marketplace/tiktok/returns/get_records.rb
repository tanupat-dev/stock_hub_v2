# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Returns
      class GetRecords
        PATH_TEMPLATE = "/return_refund/202309/returns/%{return_id}/records"

        def self.call!(shop:, return_id:)
          new(shop:, return_id:).call!
        end

        def initialize(shop:, return_id:)
          @shop = shop
          @return_id = return_id.to_s.strip
        end

        def call!
          raise ArgumentError, "shop required" if @shop.nil?
          raise ArgumentError, "return_id required" if @return_id.blank?

          client = Marketplace::Tiktok::Client.new(
            credential: @shop.tiktok_credential
          )

          client.get(
            format(PATH_TEMPLATE, return_id: @return_id),
            query: {
              "shop_cipher" => @shop.shop_cipher,
              "locale" => "en-US"
            }
          )
        end
      end
    end
  end
end

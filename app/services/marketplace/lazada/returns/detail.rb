# frozen_string_literal: true

module Marketplace
  module Lazada
    module Returns
      class Detail
        def self.call!(shop:, reverse_order_id:)
          new(shop).call!(reverse_order_id: reverse_order_id)
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @shop = shop
          @client = Marketplace::Lazada::Client.new(
            credential: @shop.lazada_credential
          )
        end

        def call!(reverse_order_id:)
          @client.get(
            "/rest/order/reverse/return/detail/list",
            params: {
              "reverse_order_id" => reverse_order_id.to_s
            }
          )
        end
      end
    end
  end
end

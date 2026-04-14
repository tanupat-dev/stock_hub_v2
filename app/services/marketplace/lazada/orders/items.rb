# frozen_string_literal: true

module Marketplace
  module Lazada
    module Orders
      class Items
        def self.call!(shop:, order_ids:)
          new(shop).call!(order_ids:)
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @client = Marketplace::Lazada::Client.new(
            credential: shop.lazada_credential
          )
        end

        def call!(order_ids:)
          ids = Array(order_ids).map(&:to_s).reject(&:blank?)
          return [] if ids.empty?

          data = @client.get(
            "/rest/orders/items/get",
            params: {
              order_ids: "[#{ids.join(",")}]"
            }
          )

          Array(data)
        end
      end
    end
  end
end

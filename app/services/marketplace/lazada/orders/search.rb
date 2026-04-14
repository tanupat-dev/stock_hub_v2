# frozen_string_literal: true

module Marketplace
  module Lazada
    module Orders
      class Search
        def self.call!(shop:, update_after:, offset: 0, limit: 100)
          new(shop).call!(update_after:, offset:, limit:)
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @shop = shop
          @client = Marketplace::Lazada::Client.new(
            credential: @shop.lazada_credential
          )
        end

        def call!(update_after:, offset:, limit:)
          data = @client.get(
            "/rest/orders/get",
            params: {
              update_after: update_after,
              offset: offset,
              limit: limit,
              sort_by: "updated_at",
              sort_direction: "ASC"
            }
          )

          {
            rows: Array(data["orders"]),
            total: data["countTotal"].to_i
          }
        end
      end
    end
  end
end

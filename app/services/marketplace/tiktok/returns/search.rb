# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Returns
      class Search
        def self.call!(shop:, update_time_ge:, update_time_lt:, page_size: 50, page_token: nil)
          new(shop:, update_time_ge:, update_time_lt:, page_size:, page_token:).call!
        end

        def initialize(shop:, update_time_ge:, update_time_lt:, page_size:, page_token:)
          @shop = shop
          @update_time_ge = update_time_ge.to_i
          @update_time_lt = update_time_lt.to_i
          @page_size = [ [ page_size.to_i, 1 ].max, 50 ].min
          @page_token = page_token
        end

        def call!
          client = Marketplace::Tiktok::Client.new(
            credential: @shop.tiktok_credential
          )

          query = {
            "shop_cipher" => @shop.shop_cipher,
            "page_size" => @page_size,
            "sort_order" => "ASC",
            "sort_field" => "update_time"
          }
          query["page_token"] = @page_token if @page_token.present?

          body = {
            "update_time_ge" => @update_time_ge,
            "update_time_lt" => @update_time_lt
          }

          data = client.post(
            "/return_refund/202602/returns/search",
            query: query,
            body: body
          )

          {
            rows: Array(data["return_orders"]),
            next_page_token: data["next_page_token"]
          }
        end
      end
    end
  end
end

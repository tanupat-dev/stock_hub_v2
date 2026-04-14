# frozen_string_literal: true

module Orders
  module Tiktok
    class SearchOrders
      DEFAULT_PAGE_SIZE = 100 # doc: Valid range [1-100]

      def self.call!(shop:, update_time_ge:, update_time_lt:, page_token: nil, page_size: DEFAULT_PAGE_SIZE)
        new(shop).call!(
          update_time_ge: update_time_ge,
          update_time_lt: update_time_lt,
          page_token: page_token,
          page_size: page_size
        )
      end

      def initialize(shop)
        @shop = shop
        raise ArgumentError, "shop required" if @shop.nil?
        raise ArgumentError, "shop_cipher missing" if @shop.shop_cipher.blank?
      end

      def call!(update_time_ge:, update_time_lt:, page_token:, page_size:)
        client = Marketplace::Tiktok::Client.new(credential: credential_for_shop!)

        query = {
          "shop_cipher" => @shop.shop_cipher,
          "page_size" => Integer(page_size),
          "sort_order" => "ASC",
          "sort_field" => "update_time"
        }
        query["page_token"] = page_token if page_token.present?

        body = {
          # polling correctness: use update_time window only (stable when sort_field=update_time ASC)
          "update_time_ge" => Integer(update_time_ge),
          "update_time_lt" => Integer(update_time_lt)
        }

        data = client.post("/order/202309/orders/search", query: query, body: body)

        {
          orders: Array(data["orders"]),
          next_page_token: data["next_page_token"].presence,
          total_count: data["total_count"]
        }
      end

      private

      def credential_for_shop!
        cred = @shop.tiktok_credential
        raise ArgumentError, "shop missing tiktok_credential" if cred.nil?
        raise "credential inactive" if cred.active == false
        cred
      end
    end
  end
end
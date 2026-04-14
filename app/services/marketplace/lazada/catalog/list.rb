# frozen_string_literal: true

require "time"

module Marketplace
  module Lazada
    module Catalog
      class List
        DEFAULT_LIMIT = 20

        def self.call!(shop:, filter: "all", limit: DEFAULT_LIMIT, offset: 0, update_after: nil, update_before: nil, sku_seller_list: nil, options: 1)
          new(shop).call!(
            filter:,
            limit:,
            offset:,
            update_after:,
            update_before:,
            sku_seller_list:,
            options:
          )
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @shop = shop
          @client = Marketplace::Lazada::Client.new(
            credential: shop.lazada_credential
          )
        end

        def call!(filter:, limit:, offset:, update_after:, update_before:, sku_seller_list:, options:)
          params = {
            filter: filter.to_s,
            limit: normalize_limit(limit),
            offset: offset.to_i,
            options: options.to_s
          }

          formatted_after = format_lazada_time(update_after)
          formatted_before = format_lazada_time(update_before)

          params[:update_after] = formatted_after if formatted_after.present?
          params[:update_before] = formatted_before if formatted_before.present?

          if sku_seller_list.present?
            arr = Array(sku_seller_list).map(&:to_s).reject(&:blank?)
            params[:sku_seller_list] = JSON.generate(arr) if arr.any?
          end

          data = @client.get("/rest/products/get", params: params)

          {
            rows: Array(data["products"]),
            total: data["total_products"].to_i
          }
        end

        private

        def normalize_limit(limit)
          n = limit.to_i
          n = DEFAULT_LIMIT if n <= 0
          n = 20 if n > 20
          n.to_s
        end

        # Lazada doc example:
        # 2018-01-01T00:00:00+0800
        def format_lazada_time(value)
          return nil if value.blank?

          t =
            case value
            when Time
              value
            else
              Time.parse(value.to_s)
            end

          t.strftime("%Y-%m-%dT%H:%M:%S%z")
        rescue
          nil
        end
      end
    end
  end
end

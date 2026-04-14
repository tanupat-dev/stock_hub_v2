# frozen_string_literal: true

module Marketplace
  module Lazada
    module Returns
      class Search
        def self.call!(shop:, modified_from_ms:, modified_to_ms:, page_no: 1, page_size: 100)
          new(shop).call!(
            modified_from_ms: modified_from_ms,
            modified_to_ms: modified_to_ms,
            page_no: page_no,
            page_size: page_size
          )
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @shop = shop
          @client = Marketplace::Lazada::Client.new(
            credential: @shop.lazada_credential
          )
        end

        def call!(modified_from_ms:, modified_to_ms:, page_no:, page_size:)
          data = @client.get(
            "/rest/reverse/getreverseordersforseller",
            params: {
              "page_no" => page_no,
              "page_size" => page_size,
              "ReverseOrderLineModifiedTimeRangeStart" => modified_from_ms.to_i,
              "ReverseOrderLineModifiedTimeRangeEnd" => modified_to_ms.to_i
            }
          )

          {
            total: data["total"].to_i,
            success: data["success"].to_s == "true",
            page_no: data["page_no"].to_i,
            page_size: data["page_size"].to_i,
            items: Array(data["items"])
          }
        end
      end
    end
  end
end

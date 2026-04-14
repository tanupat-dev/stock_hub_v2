# frozen_string_literal: true

require "cgi"

module Marketplace
  module Lazada
    module Stock
      class Update
        def self.call!(shop:, item_id:, sku_id:, seller_sku:, quantity:, reason: nil)
          new(shop).call!(
            item_id: item_id,
            sku_id: sku_id,
            seller_sku: seller_sku,
            quantity: quantity,
            reason: reason
          )
        end

        def initialize(shop)
          raise ArgumentError, "shop missing lazada_credential" if shop.lazada_credential.nil?

          @shop = shop
          @client = Marketplace::Lazada::Client.new(
            credential: shop.lazada_credential
          )
        end

        def call!(item_id:, sku_id:, seller_sku:, quantity:, reason:)
          item_id = item_id.to_s.strip
          sku_id = sku_id.to_s.strip
          seller_sku = seller_sku.to_s.strip
          qty = quantity.to_i
          qty = 0 if qty.negative?

          raise ArgumentError, "item_id required" if item_id.blank?
          raise ArgumentError, "sku_id required" if sku_id.blank?

          payload = build_payload(
            item_id: item_id,
            sku_id: sku_id,
            seller_sku: seller_sku,
            quantity: qty
          )

          Rails.logger.info(
            {
              event: "lazada.stock.update.request",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              item_id: item_id,
              sku_id: sku_id,
              seller_sku: seller_sku.presence,
              quantity: qty,
              reason: reason,
              payload_preview: payload[0, 500]
            }.to_json
          )

          data = @client.post(
            "/rest/product/stock/sellable/update",
            params: { payload: payload }
          )

          Rails.logger.info(
            {
              event: "lazada.stock.update.success",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              item_id: item_id,
              sku_id: sku_id,
              seller_sku: seller_sku.presence,
              quantity: qty,
              reason: reason,
              response_class: data.class.name,
              response_keys: data.is_a?(Hash) ? data.keys : nil
            }.to_json
          )

          data
        rescue => e
          handle_error!(
            e,
            item_id: item_id,
            sku_id: sku_id,
            seller_sku: seller_sku,
            quantity: qty,
            reason: reason
          )
        end

        private

        def build_payload(item_id:, sku_id:, seller_sku:, quantity:)
          seller_sku_xml =
            if seller_sku.present?
              "<SellerSku>#{xml_escape(seller_sku)}</SellerSku>"
            else
              ""
            end

          <<~XML.squish
            <Request>
              <Product>
                <Skus>
                  <Sku>
                    <ItemId>#{xml_escape(item_id)}</ItemId>
                    <SkuId>#{xml_escape(sku_id)}</SkuId>
                    #{seller_sku_xml}
                    <SellableQuantity>#{quantity.to_i}</SellableQuantity>
                  </Sku>
                </Skus>
              </Product>
            </Request>
          XML
        end

        def xml_escape(value)
          CGI.escapeHTML(value.to_s)
        end

        def handle_error!(error, item_id:, sku_id:, seller_sku:, quantity:, reason:)
          Rails.logger.error(
            {
              event: "lazada.stock.update.fail",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              item_id: item_id,
              sku_id: sku_id,
              seller_sku: seller_sku.presence,
              quantity: quantity,
              reason: reason,
              err_class: error.class.name,
              err_message: error.message
            }.to_json
          )

          raise
        end
      end
    end
  end
end

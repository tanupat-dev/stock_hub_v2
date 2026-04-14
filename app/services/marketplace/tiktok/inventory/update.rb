# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Inventory
      class Update
        PATH = "/product/202309/products/%{product_id}/inventory/update".freeze
        DEFAULT_WAREHOUSE_ID = "0"

        # single
        def self.call!(shop:, product_id:, external_variant_id:, quantity:, warehouse_id: nil, reason: nil)
          bulk_call!(
            shop: shop,
            product_id: product_id,
            rows: [
              {
                external_variant_id: external_variant_id,
                quantity: quantity,
                warehouse_id: warehouse_id,
                reason: reason
              }
            ]
          )
        end

        # bulk (หลาย sku ใน product เดียว)
        # rows: [{external_variant_id:, quantity:, warehouse_id:}, ...]
        def self.bulk_call!(shop:, product_id:, rows:)
          new(shop).bulk_call!(product_id: product_id, rows: rows)
        end

        def initialize(shop)
          @shop = shop
          raise ArgumentError, "shop required" if @shop.nil?
          raise ArgumentError, "shop missing credential" if @shop.tiktok_credential.nil?
          raise ArgumentError, "shop missing shop_cipher" if @shop.shop_cipher.blank?

          @client = Marketplace::Tiktok::Client.new(credential: @shop.tiktok_credential)
        end

        def bulk_call!(product_id:, rows:)
          pid = product_id.to_s.strip
          raise ArgumentError, "product_id blank" if pid.blank?

          normalized = Array(rows).map do |r|
            vid = r.fetch(:external_variant_id).to_s.strip
            qty = r.fetch(:quantity).to_i
            wid = r[:warehouse_id].to_s.strip
            wid = DEFAULT_WAREHOUSE_ID if wid.blank?

            raise ArgumentError, "external_variant_id blank" if vid.blank?
            raise ArgumentError, "quantity invalid (#{qty})" if qty < 0

            { id: vid, inventory: [ { warehouse_id: wid, quantity: qty } ] }
          end

          body = { skus: normalized }
          path = PATH % { product_id: pid }

          Rails.logger.info(
            {
              event: "tiktok.inventory.update.request",
              shop_id: @shop.id,
              product_id: pid,
              sku_count: normalized.size,
              sample: normalized.first(3)
            }.to_json
          )

          data = @client.post(path, query: { "shop_cipher" => @shop.shop_cipher }, body: body)

          # TikTok จะคืน code=0 แต่ยังมี data.errors ได้ → ต้อง treat เป็น fail
          errors = Array(data["errors"])
          if errors.any?
            Rails.logger.error(
              {
                event: "tiktok.inventory.update.partial_error",
                shop_id: @shop.id,
                product_id: pid,
                errors: errors.first(10)
              }.to_json
            )
            raise Marketplace::Tiktok::Errors::Error.new(
              "inventory update returned errors",
              code: 0,
              request_id: nil
            )
          end

          Rails.logger.info(
            {
              event: "tiktok.inventory.update.success",
              shop_id: @shop.id,
              product_id: pid,
              sku_count: normalized.size
            }.to_json
          )

          data
        end
      end
    end
  end
end

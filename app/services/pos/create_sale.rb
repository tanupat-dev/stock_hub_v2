# app/services/pos/create_sale.rb
# frozen_string_literal: true

module Pos
  class CreateSale
    def self.call!(shop:, idempotency_key:, meta: {})
      new(shop:, idempotency_key:, meta:).call!
    end

    def initialize(shop:, idempotency_key:, meta:)
      @shop = shop
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "shop is required" if @shop.nil?

      PosSale.transaction do
        existing = PosSale.find_by(idempotency_key: @idempotency_key)
        return existing if existing

        sale = PosSale.create!(
          shop: @shop,
          sale_number: generate_sale_number,
          status: "cart",
          item_count: 0,
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        Rails.logger.info({
          event: "pos.create_sale",
          sale_id: sale.id,
          shop_id: @shop.id,
          idempotency_key: @idempotency_key
        }.to_json)

        sale
      end
    end

    private

    def generate_sale_number
      "POS-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
    end
  end
end

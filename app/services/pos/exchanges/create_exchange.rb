# frozen_string_literal: true

module Pos
  module Exchanges
    class CreateExchange
      class SaleNotCheckedOut < StandardError; end
      class SaleVoided < StandardError; end
      class ShopMismatch < StandardError; end

      def self.call!(shop:, pos_sale:, idempotency_key:, meta: {})
        new(shop:, pos_sale:, idempotency_key:, meta:).call!
      end

      def initialize(shop:, pos_sale:, idempotency_key:, meta:)
        @shop = shop
        @pos_sale = pos_sale
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "shop is required" if @shop.nil?
        raise ArgumentError, "pos_sale is required" if @pos_sale.nil?
        raise ArgumentError, "idempotency_key is required" if @idempotency_key.to_s.blank?

        raise ShopMismatch, "pos sale does not belong to shop" if @pos_sale.shop_id != @shop.id
        raise SaleVoided, "pos sale is voided" if @pos_sale.voided?
        raise SaleNotCheckedOut, "pos sale must be checked_out" unless @pos_sale.checked_out?

        PosExchange.transaction do
          existing = PosExchange.find_by(idempotency_key: @idempotency_key)
          return existing if existing

          exchange = PosExchange.create!(
            shop: @shop,
            pos_sale: @pos_sale,
            exchange_number: generate_exchange_number,
            status: "open",
            idempotency_key: @idempotency_key,
            meta: @meta
          )

          Rails.logger.info(
            {
              event: "pos_exchange.create",
              pos_exchange_id: exchange.id,
              pos_sale_id: @pos_sale.id,
              shop_id: @shop.id,
              idempotency_key: @idempotency_key
            }.to_json
          )

          exchange
        end
      end

      private

      def generate_exchange_number
        "PX-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
      end
    end
  end
end

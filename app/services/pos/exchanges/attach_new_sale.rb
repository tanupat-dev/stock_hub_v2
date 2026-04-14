# frozen_string_literal: true

module Pos
  module Exchanges
    class AttachNewSale
      class ExchangeNotOpen < StandardError; end
      class ShopMismatch < StandardError; end
      class SameSaleNotAllowed < StandardError; end
      class SaleVoided < StandardError; end
      class SaleAlreadyAttached < StandardError; end

      def self.call!(pos_exchange:, new_pos_sale:, idempotency_key:, meta: {})
        new(pos_exchange:, new_pos_sale:, idempotency_key:, meta:).call!
      end

      def initialize(pos_exchange:, new_pos_sale:, idempotency_key:, meta:)
        @pos_exchange = pos_exchange
        @new_pos_sale = new_pos_sale
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "pos_exchange is required" if @pos_exchange.nil?
        raise ArgumentError, "new_pos_sale is required" if @new_pos_sale.nil?

        PosExchange.transaction do
          @pos_exchange.lock!
          @pos_exchange.reload

          return @pos_exchange if replay?

          raise ExchangeNotOpen, "pos exchange is not open" unless @pos_exchange.open?
          raise ShopMismatch, "new pos sale does not belong to exchange shop" if @new_pos_sale.shop_id != @pos_exchange.shop_id
          raise SameSaleNotAllowed, "new pos sale must be different from original pos sale" if @new_pos_sale.id == @pos_exchange.pos_sale_id
          raise SaleVoided, "new pos sale is voided" if @new_pos_sale.voided?

          existing_exchange = PosExchange.where(new_pos_sale_id: @new_pos_sale.id, status: "open").where.not(id: @pos_exchange.id).first
          raise SaleAlreadyAttached, "new pos sale is already attached to another open exchange" if existing_exchange.present?

          @pos_exchange.update!(
            new_pos_sale: @new_pos_sale,
            meta: @pos_exchange.meta.merge(
              "attach_new_sale_meta" => @meta,
              "attach_new_sale_idempotency_key" => @idempotency_key
            )
          )

          Rails.logger.info(
            {
              event: "pos_exchange.attach_new_sale",
              pos_exchange_id: @pos_exchange.id,
              new_pos_sale_id: @new_pos_sale.id,
              idempotency_key: @idempotency_key
            }.to_json
          )

          @pos_exchange
        end
      end

      private

      def replay?
        @pos_exchange.new_pos_sale_id == @new_pos_sale.id &&
          @pos_exchange.meta.to_h["attach_new_sale_idempotency_key"] == @idempotency_key
      end
    end
  end
end

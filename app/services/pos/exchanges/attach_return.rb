# frozen_string_literal: true

module Pos
  module Exchanges
    class AttachReturn
      class ExchangeNotOpen < StandardError; end
      class ReturnSaleMismatch < StandardError; end
      class ShopMismatch < StandardError; end

      def self.call!(pos_exchange:, pos_return:, idempotency_key:, meta: {})
        new(pos_exchange:, pos_return:, idempotency_key:, meta:).call!
      end

      def initialize(pos_exchange:, pos_return:, idempotency_key:, meta:)
        @pos_exchange = pos_exchange
        @pos_return = pos_return
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "pos_exchange is required" if @pos_exchange.nil?
        raise ArgumentError, "pos_return is required" if @pos_return.nil?

        PosExchange.transaction do
          @pos_exchange.lock!
          @pos_exchange.reload

          return @pos_exchange if replay?

          raise ExchangeNotOpen, "pos exchange is not open" unless @pos_exchange.open?
          raise ShopMismatch, "pos return does not belong to exchange shop" if @pos_return.shop_id != @pos_exchange.shop_id
          raise ReturnSaleMismatch, "pos return does not belong to exchange pos_sale" if @pos_return.pos_sale_id != @pos_exchange.pos_sale_id

          @pos_exchange.update!(
            pos_return: @pos_return,
            meta: @pos_exchange.meta.merge(
              "attach_return_meta" => @meta,
              "attach_return_idempotency_key" => @idempotency_key
            )
          )

          Rails.logger.info(
            {
              event: "pos_exchange.attach_return",
              pos_exchange_id: @pos_exchange.id,
              pos_return_id: @pos_return.id,
              idempotency_key: @idempotency_key
            }.to_json
          )

          @pos_exchange
        end
      end

      private

      def replay?
        @pos_exchange.pos_return_id == @pos_return.id &&
          @pos_exchange.meta.to_h["attach_return_idempotency_key"] == @idempotency_key
      end
    end
  end
end

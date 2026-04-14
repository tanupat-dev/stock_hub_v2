# frozen_string_literal: true

module Pos
  module Exchanges
    class CompleteExchange
      class ExchangeNotOpen < StandardError; end
      class MissingReturn < StandardError; end
      class MissingNewSale < StandardError; end
      class ReturnNotCompleted < StandardError; end
      class NewSaleNotCheckedOut < StandardError; end
      class ShopMismatch < StandardError; end
      class SaleMismatch < StandardError; end

      def self.call!(pos_exchange:, idempotency_key:, meta: {})
        new(pos_exchange:, idempotency_key:, meta:).call!
      end

      def initialize(pos_exchange:, idempotency_key:, meta:)
        @pos_exchange = pos_exchange
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "pos_exchange is required" if @pos_exchange.nil?

        PosExchange.transaction do
          @pos_exchange.lock!
          @pos_exchange.reload

          return @pos_exchange if replay?

          raise ExchangeNotOpen, "pos exchange is not open" unless @pos_exchange.open?
          raise MissingReturn, "pos exchange missing pos_return" if @pos_exchange.pos_return.nil?
          raise MissingNewSale, "pos exchange missing new_pos_sale" if @pos_exchange.new_pos_sale.nil?

          raise ShopMismatch, "pos return shop mismatch" if @pos_exchange.pos_return.shop_id != @pos_exchange.shop_id
          raise ShopMismatch, "new pos sale shop mismatch" if @pos_exchange.new_pos_sale.shop_id != @pos_exchange.shop_id
          raise SaleMismatch, "pos return does not belong to exchange pos_sale" if @pos_exchange.pos_return.pos_sale_id != @pos_exchange.pos_sale_id

          raise ReturnNotCompleted, "pos return must be completed" unless @pos_exchange.pos_return.completed?
          raise NewSaleNotCheckedOut, "new pos sale must be checked_out" unless @pos_exchange.new_pos_sale.checked_out?

          @pos_exchange.update!(
            status: "completed",
            completed_at: Time.current,
            meta: @pos_exchange.meta.merge(
              "complete_meta" => @meta,
              "complete_idempotency_key" => @idempotency_key
            )
          )

          Rails.logger.info(
            {
              event: "pos_exchange.complete",
              pos_exchange_id: @pos_exchange.id,
              pos_sale_id: @pos_exchange.pos_sale_id,
              pos_return_id: @pos_exchange.pos_return_id,
              new_pos_sale_id: @pos_exchange.new_pos_sale_id,
              idempotency_key: @idempotency_key
            }.to_json
          )

          @pos_exchange
        end
      end

      private

      def replay?
        @pos_exchange.completed? &&
          @pos_exchange.meta.to_h["complete_idempotency_key"] == @idempotency_key
      end
    end
  end
end

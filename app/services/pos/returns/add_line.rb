# frozen_string_literal: true

module Pos
  module Returns
    class AddLine
      class ReturnNotOpen < StandardError; end
      class SaleLineMismatch < StandardError; end
      class ReturnExceedsSold < StandardError; end
      class SaleNotCheckedOut < StandardError; end
      class SaleVoided < StandardError; end
      class SaleLineNotActive < StandardError; end

      def self.call!(pos_return:, pos_sale_line:, quantity:, idempotency_key:, meta: {})
        new(pos_return:, pos_sale_line:, quantity:, idempotency_key:, meta:).call!
      end

      def initialize(pos_return:, pos_sale_line:, quantity:, idempotency_key:, meta:)
        @pos_return = pos_return
        @pos_sale_line = pos_sale_line
        @quantity = quantity.to_i
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "pos_return is required" if @pos_return.nil?
        raise ArgumentError, "pos_sale_line is required" if @pos_sale_line.nil?
        raise ArgumentError, "quantity must be > 0" if @quantity <= 0

        PosReturnLine.transaction do
          existing = PosReturnLine.find_by(idempotency_key: @idempotency_key)
          return existing if existing

          @pos_return.lock!
          @pos_return.reload

          sale = @pos_return.pos_sale

          raise ReturnNotOpen, "pos return is not open" unless @pos_return.open?
          raise SaleVoided, "pos sale is voided" if sale.voided?
          raise SaleNotCheckedOut, "pos sale must be checked_out" unless sale.checked_out?
          raise SaleLineMismatch, "pos_sale_line does not belong to pos_return.pos_sale" if @pos_sale_line.pos_sale_id != @pos_return.pos_sale_id
          raise SaleLineNotActive, "pos sale line is not active" unless @pos_sale_line.active?

          already_returned = @pos_sale_line.returned_qty
          remaining = @pos_sale_line.quantity.to_i - already_returned
          raise ReturnExceedsSold, "return exceeds sold qty (remaining=#{remaining}, request=#{@quantity})" if @quantity > remaining

          line = PosReturnLine.create!(
            pos_return: @pos_return,
            pos_sale_line: @pos_sale_line,
            sku: @pos_sale_line.sku,
            quantity: @quantity,
            barcode_snapshot: @pos_sale_line.barcode_snapshot,
            sku_code_snapshot: @pos_sale_line.sku_code_snapshot,
            idempotency_key: @idempotency_key,
            meta: @meta
          )

          Rails.logger.info(
            {
              event: "pos_return.add_line",
              pos_return_id: @pos_return.id,
              pos_return_line_id: line.id,
              pos_sale_line_id: @pos_sale_line.id,
              sku: @pos_sale_line.sku_code_snapshot,
              quantity: @quantity,
              idempotency_key: @idempotency_key
            }.to_json
          )

          line
        end
      rescue ActiveRecord::RecordNotUnique
        PosReturnLine.find_by(idempotency_key: @idempotency_key)
      end
    end
  end
end

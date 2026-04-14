# frozen_string_literal: true

module Pos
  class UpdateLineQuantity
    def self.call!(line:, quantity:, idempotency_key:, meta: {})
      new(line:, quantity:, idempotency_key:, meta:).call!
    end

    def initialize(line:, quantity:, idempotency_key:, meta:)
      @line = line
      @quantity = quantity.to_i
      @idempotency_key = idempotency_key.to_s
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "line is required" if @line.nil?
      raise ArgumentError, "quantity must be > 0" if @quantity <= 0
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      PosSaleLine.transaction do
        @line.lock!
        @line.reload

        raise "sale is not cart" unless @line.pos_sale.cart?

        if replay?
          Rails.logger.info(
            {
              event: "pos.update_line_quantity.replay",
              line_id: @line.id,
              sale_id: @line.pos_sale.id,
              quantity: @line.quantity,
              idempotency_key: @idempotency_key
            }.to_json
          )
          return @line
        end

        @line.update!(
          quantity: @quantity,
          meta: @line.meta.to_h.merge(
            "last_update_line_idempotency_key" => @idempotency_key,
            "last_update_line_meta" => @meta
          )
        )

        @line.pos_sale.recalculate_item_count!

        Rails.logger.info(
          {
            event: "pos.update_line_quantity",
            line_id: @line.id,
            sale_id: @line.pos_sale.id,
            quantity: @quantity,
            idempotency_key: @idempotency_key
          }.to_json
        )

        @line
      end
    end

    private

    def replay?
      @line.meta.to_h["last_update_line_idempotency_key"] == @idempotency_key
    end
  end
end

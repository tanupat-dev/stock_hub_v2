# frozen_string_literal: true

module Pos
  class RemoveLine
    def self.call!(line:, idempotency_key:, meta: {})
      new(line:, idempotency_key:, meta:).call!
    end

    def initialize(line:, idempotency_key:, meta:)
      @line = line
      @idempotency_key = idempotency_key.to_s
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "line is required" if @line.nil?
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      PosSaleLine.transaction do
        @line.lock!
        @line.reload

        raise "sale is not cart" unless @line.pos_sale.cart?

        if replay?
          Rails.logger.info(
            {
              event: "pos.remove_line.replay",
              line_id: @line.id,
              sale_id: @line.pos_sale.id,
              idempotency_key: @idempotency_key
            }.to_json
          )
          return @line
        end

        if @line.voided?
          @line.update!(
            meta: @line.meta.to_h.merge(
              "last_remove_line_idempotency_key" => @idempotency_key,
              "last_remove_line_meta" => @meta
            )
          )
          return @line
        end

        @line.update!(
          status: "voided",
          meta: @line.meta.to_h.merge(
            "last_remove_line_idempotency_key" => @idempotency_key,
            "last_remove_line_meta" => @meta
          )
        )

        @line.pos_sale.recalculate_item_count!

        Rails.logger.info(
          {
            event: "pos.remove_line",
            line_id: @line.id,
            sale_id: @line.pos_sale.id,
            idempotency_key: @idempotency_key
          }.to_json
        )

        @line
      end
    end

    private

    def replay?
      @line.meta.to_h["last_remove_line_idempotency_key"] == @idempotency_key
    end
  end
end

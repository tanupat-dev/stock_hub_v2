# frozen_string_literal: true

module Pos
  class AddLine
    def self.call!(sale:, sku:, quantity:, idempotency_key:, meta: {})
      new(sale:, sku:, quantity:, idempotency_key:, meta:).call!
    end

    def initialize(sale:, sku:, quantity:, idempotency_key:, meta:)
      @sale = sale
      @sku = sku
      @quantity = quantity.to_i
      @idempotency_key = idempotency_key.to_s
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "sale is required" if @sale.nil?
      raise ArgumentError, "sku is required" if @sku.nil?
      raise ArgumentError, "quantity must be > 0" if @quantity <= 0
      raise "sale is not cart" unless @sale.cart?
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      PosSaleLine.transaction do
        @sale.lock!
        @sale.reload

        existing = find_replay_line
        return existing if existing.present?

        line = @sale.pos_sale_lines.active_lines.find_by(sku_id: @sku.id)

        if line
          line.update!(
            quantity: line.quantity + @quantity,
            meta: line.meta.to_h.merge(
              "last_add_line_idempotency_key" => @idempotency_key,
              "last_add_line_meta" => @meta
            )
          )
        else
          line = PosSaleLine.create!(
            pos_sale: @sale,
            sku: @sku,
            status: "active",
            barcode_snapshot: @sku.barcode,
            sku_code_snapshot: @sku.code,
            quantity: @quantity,
            idempotency_key: @idempotency_key,
            meta: @meta.merge(
              "created_by" => "pos.add_line"
            )
          )
        end

        @sale.recalculate_item_count!

        Rails.logger.info(
          {
            event: "pos.add_line",
            sale_id: @sale.id,
            sku: @sku.code,
            quantity: @quantity,
            new_quantity: line.quantity,
            idempotency_key: @idempotency_key
          }.to_json
        )

        line
      end
    rescue ActiveRecord::RecordNotUnique
      find_replay_line || @sale.pos_sale_lines.active_lines.find_by(sku_id: @sku.id)
    end

    private

    def find_replay_line
      @sale.pos_sale_lines.find_by(idempotency_key: @idempotency_key) ||
        @sale.pos_sale_lines.find_by("meta ->> 'last_add_line_idempotency_key' = ?", @idempotency_key)
    end
  end
end

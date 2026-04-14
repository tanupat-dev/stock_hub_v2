# frozen_string_literal: true

module StockCount
  class UpsertLine
    class SessionNotOpen < StandardError; end

    def self.call!(session:, sku:, counted_qty:, idempotency_key:, meta: {})
      new(session:, sku:, counted_qty:, idempotency_key:, meta:).call!
    end

    def initialize(session:, sku:, counted_qty:, idempotency_key:, meta:)
      @session = session
      @sku = sku
      @counted_qty = counted_qty.to_i
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "session is required" if @session.nil?
      raise ArgumentError, "sku is required" if @sku.nil?
      raise ArgumentError, "counted_qty must be >= 0" if @counted_qty.negative?

      StockCountLine.transaction do
        existing_by_key = StockCountLine.find_by(idempotency_key: @idempotency_key)
        return existing_by_key if existing_by_key

        @session.lock!
        @session.reload

        raise SessionNotOpen, "stock count session is not open" unless @session.open?

        line = @session.stock_count_lines.lock.find_by(sku_id: @sku.id)

        system_qty = @sku.inventory_balance&.on_hand.to_i
        diff_qty = @counted_qty - system_qty

        if line
          line.update!(
            barcode_snapshot: @sku.barcode,
            sku_code_snapshot: @sku.code,
            system_qty_snapshot: system_qty,
            counted_qty: @counted_qty,
            diff_qty: diff_qty,
            meta: line.meta.merge(@meta)
          )
        else
          line = StockCountLine.create!(
            stock_count_session: @session,
            sku: @sku,
            barcode_snapshot: @sku.barcode,
            sku_code_snapshot: @sku.code,
            system_qty_snapshot: system_qty,
            counted_qty: @counted_qty,
            diff_qty: diff_qty,
            status: "pending",
            idempotency_key: @idempotency_key,
            meta: @meta
          )
        end

        Rails.logger.info(
          {
            event: "stock_count.upsert_line",
            stock_count_session_id: @session.id,
            stock_count_line_id: line.id,
            sku_id: @sku.id,
            sku: @sku.code,
            system_qty_snapshot: system_qty,
            counted_qty: @counted_qty,
            diff_qty: diff_qty,
            idempotency_key: @idempotency_key
          }.to_json
        )

        line
      end
    rescue ActiveRecord::RecordNotUnique
      StockCountLine.find_by(idempotency_key: @idempotency_key)
    end
  end
end

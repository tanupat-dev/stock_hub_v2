# frozen_string_literal: true

module StockCount
  class ConfirmSession
    class SessionNotOpen < StandardError; end
    class EmptySession < StandardError; end

    def self.call!(session:, idempotency_key:, meta: {})
      new(session:, idempotency_key:, meta:).call!
    end

    def initialize(session:, idempotency_key:, meta:)
      @session = session
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "session is required" if @session.nil?

      StockCountSession.transaction do
        @session.lock!
        @session.reload

        return @session if already_confirmed_by_same_request?

        raise SessionNotOpen, "stock count session is not open" unless @session.open?

        lines = @session.stock_count_lines.includes(:sku).order(:id).to_a
        raise EmptySession, "stock count session has no lines" if lines.empty?

        results = []

        lines.each do |line|
          line.lock!

          result =
            if line.diff_qty.zero?
              :no_change
            else
              Inventory::Adjust.call!(
                sku: line.sku,
                set_to: line.counted_qty,
                idempotency_key: build_line_idempotency_key(line),
                meta: {
                  source: "stock_count_confirm",
                  stock_count_session_id: @session.id,
                  stock_count_line_id: line.id
                }
              )
            end

          line.update!(status: "confirmed")

          results << {
            stock_count_line_id: line.id,
            sku: line.sku.code,
            system_qty_snapshot: line.system_qty_snapshot,
            counted_qty: line.counted_qty,
            diff_qty: line.diff_qty,
            result: result
          }
        end

        @session.update!(
          status: "confirmed",
          confirmed_at: Time.current,
          meta: @session.meta.merge(
            "confirm_meta" => @meta,
            "confirm_idempotency_key" => @idempotency_key
          )
        )

        Rails.logger.info(
          {
            event: "stock_count.confirm_session",
            stock_count_session_id: @session.id,
            session_number: @session.session_number,
            line_count: lines.size,
            idempotency_key: @idempotency_key,
            results: results
          }.to_json
        )

        @session
      end
    end

    private

    def already_confirmed_by_same_request?
      @session.confirmed? && @session.meta.to_h["confirm_idempotency_key"] == @idempotency_key
    end

    def build_line_idempotency_key(line)
      "stock_count:confirm:session=#{@session.id}:line=#{line.id}"
    end
  end
end

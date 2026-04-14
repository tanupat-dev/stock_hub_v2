# frozen_string_literal: true

module Pos
  module Returns
    class CompleteReturn
      class ReturnNotOpen < StandardError; end
      class EmptyReturn < StandardError; end

      def self.call!(pos_return:, idempotency_key:, meta: {})
        new(pos_return:, idempotency_key:, meta:).call!
      end

      def initialize(pos_return:, idempotency_key:, meta:)
        @pos_return = pos_return
        @idempotency_key = idempotency_key
        @meta = meta || {}
      end

      def call!
        raise ArgumentError, "pos_return is required" if @pos_return.nil?

        PosReturn.transaction do
          @pos_return.lock!
          @pos_return.reload

          # ===== idempotency replay =====
          if already_completed_by_same_request?
            Rails.logger.info(
              {
                event: "pos_return.complete.replay",
                pos_return_id: @pos_return.id,
                idempotency_key: @idempotency_key
              }.to_json
            )
            return @pos_return
          end

          raise ReturnNotOpen, "pos return is not open" unless @pos_return.open?

          lines = @pos_return.pos_return_lines.includes(:sku).order(:id).to_a
          raise EmptyReturn, "pos return has no lines" if lines.empty?

          results = []

          lines.each do |line|
            result = Inventory::StockIn.call!(
              sku: line.sku,
              quantity: line.quantity,
              idempotency_key: build_line_idempotency_key(line),
              meta: {
                source: "pos_return_complete",
                pos_return_id: @pos_return.id,
                pos_return_line_id: line.id,
                pos_sale_id: @pos_return.pos_sale_id,
                pos_sale_line_id: line.pos_sale_line_id
              }
            )

            results << {
              pos_return_line_id: line.id,
              sku: line.sku.code,
              quantity: line.quantity,
              result: result
            }
          end

          @pos_return.update!(
            status: "completed",
            completed_at: Time.current,
            meta: @pos_return.meta.merge(
              "complete_meta" => @meta,
              "complete_idempotency_key" => @idempotency_key
            )
          )

          Rails.logger.info(
            {
              event: "pos_return.complete",
              pos_return_id: @pos_return.id,
              pos_sale_id: @pos_return.pos_sale_id,
              line_count: lines.size,
              idempotency_key: @idempotency_key,
              results: results
            }.to_json
          )

          @pos_return
        end
      end

      private

      def already_completed_by_same_request?
        @pos_return.completed? &&
          @pos_return.meta.to_h["complete_idempotency_key"] == @idempotency_key
      end

      def build_line_idempotency_key(line)
        "pos:return:complete:return=#{@pos_return.id}:line=#{line.id}"
      end
    end
  end
end

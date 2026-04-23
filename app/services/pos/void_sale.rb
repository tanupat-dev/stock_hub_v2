# frozen_string_literal: true

module Pos
  class VoidSale
    class SaleNotCheckedOut < StandardError; end
    class SaleAlreadyVoided < StandardError; end
    class EmptySale < StandardError; end
    class SaleNotCart < StandardError; end

    def self.call!(sale:, idempotency_key:, meta: {})
      new(sale:, idempotency_key:, meta:).call!
    end

    def initialize(sale:, idempotency_key:, meta:)
      @sale = sale
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "sale is required" if @sale.nil?

      affected_skus = []

      PosSale.transaction do
        @sale.lock!
        @sale.reload

        return @sale if already_voided_by_same_request?

        raise SaleAlreadyVoided, "sale already voided" if @sale.voided?
        raise SaleNotCheckedOut, "sale is not checked_out" unless @sale.checked_out?

        lines = @sale.pos_sale_lines.active_lines.includes(:sku).order(:id).to_a
        raise EmptySale, "no active lines in sale" if lines.empty?

        results = []

        lines.each do |line|
          res = Inventory::StockIn.call!(
            sku: line.sku,
            quantity: line.quantity,
            idempotency_key: build_line_idempotency_key(line),
            meta: {
              source: "pos_void_sale",
              pos_sale_id: @sale.id,
              pos_sale_line_id: line.id
            }
          )

          line.update!(status: "voided")
          affected_skus << line.sku if line.sku.present?

          results << {
            sku: line.sku.code,
            quantity: line.quantity,
            result: res
          }
        end

        now = Time.current

        @sale.update!(
          status: "voided",
          voided_at: now,
          meta: @sale.meta.merge(
            "void_meta" => @meta,
            "void_idempotency_key" => @idempotency_key
          )
        )

        Rails.logger.info(
          {
            event: "pos.void_sale.success",
            sale_id: @sale.id,
            item_count: @sale.item_count,
            lines: results,
            idempotency_key: @idempotency_key
          }.to_json
        )
      end

      affected_skus.uniq(&:id).each do |sku|
        Inventory::UnfreezeIfResolved.call!(
          sku: sku,
          trigger: "pos_void_sale",
          meta: {
            source: "pos_void_sale",
            pos_sale_id: @sale.id
          }
        )

        Inventory::ResolveOversellIncidents.call!(
          sku: sku,
          trigger: "pos_void_sale",
          meta: {
            source: "pos_void_sale",
            pos_sale_id: @sale.id
          }
        )
      end

      @sale.reload
    rescue => e
      Rails.logger.error(
        {
          event: "pos.void_sale.error",
          sale_id: @sale&.id,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
      raise
    end

    def cancel_cart!
      raise ArgumentError, "sale is required" if @sale.nil?

      PosSale.transaction do
        @sale.lock!
        @sale.reload

        return @sale if already_voided_by_same_request?

        raise SaleAlreadyVoided, "sale already voided" if @sale.voided?
        raise SaleNotCart, "sale is not cart" unless @sale.cart?

        now = Time.current
        lines = @sale.pos_sale_lines.active_lines.order(:id).to_a
        line_ids = lines.map(&:id)

        if line_ids.any?
          PosSaleLine.where(id: line_ids).update_all(
            status: "voided",
            updated_at: now
          )
        end

        @sale.update!(
          status: "voided",
          voided_at: now,
          item_count: 0,
          meta: @sale.meta.merge(
            "void_meta" => @meta,
            "void_idempotency_key" => @idempotency_key,
            "void_reason" => "cancel_cart"
          )
        )

        Rails.logger.info(
          {
            event: "pos.cancel_cart.success",
            sale_id: @sale.id,
            line_ids: line_ids,
            idempotency_key: @idempotency_key
          }.to_json
        )
      end

      @sale.reload
    rescue => e
      Rails.logger.error(
        {
          event: "pos.cancel_cart.error",
          sale_id: @sale&.id,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
      raise
    end

    private

    def already_voided_by_same_request?
      @sale.voided? && @sale.meta.to_h["void_idempotency_key"] == @idempotency_key
    end

    def build_line_idempotency_key(line)
      "pos:void_sale:sale=#{@sale.id}:line=#{line.id}"
    end
  end
end

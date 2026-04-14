# frozen_string_literal: true

module Pos
  class CheckoutSale
    class SaleNotCart < StandardError; end
    class EmptySale < StandardError; end
    class InsufficientStock < StandardError; end

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

      oversell_checks = []

      PosSale.transaction do
        @sale.lock!

        if @sale.checked_out? &&
           @sale.meta.to_h["checkout_idempotency_key"] == @idempotency_key
          Rails.logger.info(
            {
              event: "pos.checkout.replay",
              sale_id: @sale.id,
              idempotency_key: @idempotency_key
            }.to_json
          )
          return @sale
        end

        raise SaleNotCart, "sale is not cart" unless @sale.cart?

        lines = @sale.pos_sale_lines.active_lines.includes(:sku).order(:sku_id, :id).to_a
        raise EmptySale, "no items in sale" if lines.empty?

        qty_by_sku_id = lines.each_with_object(Hash.new(0)) do |line, memo|
          memo[line.sku_id] += line.quantity.to_i
        end

        balances_by_sku_id = {}

        qty_by_sku_id.keys.sort.each do |sku_id|
          sku = lines.find { |line| line.sku_id == sku_id }&.sku
          next if sku.nil?

          balance = Inventory::BalanceFetcher.fetch_for_update!(sku: sku)
          balances_by_sku_id[sku_id] = balance

          needed = qty_by_sku_id.fetch(sku_id).to_i
          on_hand = balance.on_hand.to_i

          if on_hand < needed
            raise InsufficientStock, "SKU #{sku.code} not enough stock (have=#{on_hand}, need=#{needed})"
          end
        end

        results = []

        lines.each do |line|
          sku = line.sku
          qty = line.quantity.to_i

          res = Inventory::CommitPos.call!(
            sku: sku,
            quantity: qty,
            idempotency_key: build_line_idempotency_key(line),
            meta: {
              source: "pos_checkout",
              pos_sale_id: @sale.id,
              pos_sale_line_id: line.id
            }
          )

          results << {
            sku: sku.code,
            quantity: qty,
            result: res
          }

          oversell_checks << {
            sku: sku,
            idempotency_key: "oversell:pos_checkout:sale=#{@sale.id}:sku=#{sku.id}",
            meta: {
              source: "pos_checkout",
              pos_sale_id: @sale.id,
              pos_sale_line_id: line.id
            }
          }
        end

        now = Time.current

        @sale.update!(
          status: "checked_out",
          checked_out_at: now,
          meta: @sale.meta.merge(
            "checkout_meta" => @meta,
            "checkout_idempotency_key" => @idempotency_key
          )
        )

        Rails.logger.info(
          {
            event: "pos.checkout.success",
            sale_id: @sale.id,
            item_count: @sale.item_count,
            lines: results,
            idempotency_key: @idempotency_key
          }.to_json
        )
      end

      oversell_checks
        .uniq { |entry| entry[:sku].id }
        .each do |entry|
          Inventory::OversellGuard.call!(
            sku: entry.fetch(:sku),
            trigger: "pos_checkout",
            idempotency_key: entry.fetch(:idempotency_key),
            meta: entry.fetch(:meta)
          )
        end

      @sale.reload
    rescue Inventory::CommitPos::OnHandWouldGoNegative => e
      Rails.logger.warn(
        {
          event: "pos.checkout.fail",
          sale_id: @sale&.id,
          reason: "commit_negative",
          err: e.message
        }.to_json
      )

      raise InsufficientStock, e.message
    rescue => e
      Rails.logger.error(
        {
          event: "pos.checkout.error",
          sale_id: @sale&.id,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )

      raise
    end

    private

    def build_line_idempotency_key(line)
      "pos:checkout:sale=#{@sale.id}:line=#{line.id}"
    end
  end
end

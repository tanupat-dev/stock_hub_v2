# frozen_string_literal: true

module Inventory
  class BindBarcode
    class BarcodeBlank < StandardError; end
    class SkuRequired < StandardError; end
    class BarcodeAlreadyAssigned < StandardError; end
    class BarcodeAlreadyBoundOnSku < StandardError; end

    def self.call!(sku:, barcode:, force: false, meta: {})
      new(sku:, barcode:, force:, meta:).call!
    end

    def initialize(sku:, barcode:, force:, meta:)
      @sku = sku
      @barcode = normalize_barcode(barcode)
      @force = force
      @meta = meta || {}
    end

    def call!
      raise SkuRequired, "sku is required" if @sku.nil?
      raise BarcodeBlank, "barcode is blank" if @barcode.blank?

      result = nil

      Sku.transaction do
        @sku.lock!

        existing = Sku.lock.where(barcode: @barcode).where.not(id: @sku.id).first
        if existing.present?
          raise BarcodeAlreadyAssigned,
                "barcode #{@barcode} already assigned to sku #{existing.code} (id=#{existing.id})"
        end

        if @sku.barcode == @barcode
          result = :already_bound
        elsif @sku.barcode.present? && !@force
          raise BarcodeAlreadyBoundOnSku,
                "sku #{@sku.code} already has barcode #{@sku.barcode}; use force=true to replace"
        else
          old_barcode = @sku.barcode
          @sku.update!(barcode: @barcode)

          Rails.logger.info(
            {
              event: "inventory.bind_barcode",
              sku_id: @sku.id,
              sku: @sku.code,
              old_barcode: old_barcode,
              new_barcode: @barcode,
              force: @force,
              meta: @meta
            }.to_json
          )

          result = old_barcode.present? ? :replaced : :bound
        end
      end

      result
    end

    private

    def normalize_barcode(value)
      value.to_s.gsub(/\s+/, "").strip
    end
  end
end

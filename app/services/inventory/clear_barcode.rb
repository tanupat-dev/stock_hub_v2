# frozen_string_literal: true

module Inventory
  class ClearBarcode
    class SkuRequired < StandardError; end

    def self.call!(sku:, meta: {})
      new(sku:, meta:).call!
    end

    def initialize(sku:, meta:)
      @sku = sku
      @meta = meta || {}
    end

    def call!
      raise SkuRequired, "sku is required" if @sku.nil?

      result = nil

      Sku.transaction do
        @sku.lock!

        if @sku.barcode.blank?
          result = :already_blank
        else
          old_barcode = @sku.barcode
          @sku.update!(barcode: nil)

          Rails.logger.info(
            {
              event: "inventory.clear_barcode",
              sku_id: @sku.id,
              sku: @sku.code,
              old_barcode: old_barcode,
              meta: @meta
            }.to_json
          )

          result = :cleared
        end
      end

      result
    end
  end
end

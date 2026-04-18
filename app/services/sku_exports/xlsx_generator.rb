# frozen_string_literal: true

require "caxlsx"
require "fileutils"

module SkuExports
  class XlsxGenerator
    def self.call(skus:, output_path:)
      new(skus:, output_path:).call
    end

    def initialize(skus:, output_path:)
      @skus = Array(skus)
      @output_path = output_path
    end

    def call
      FileUtils.mkdir_p(File.dirname(output_path))

      package = Axlsx::Package.new
      workbook = package.workbook

      workbook.add_worksheet(name: "SKUs") do |sheet|
        build_header(sheet)
        build_rows(sheet)
        set_column_widths(sheet)
      end

      package.serialize(output_path)
      output_path
    end

    private

    attr_reader :skus, :output_path

    def build_header(sheet)
      sheet.add_row [
        "sku",
        "brand",
        "model",
        "color",
        "size",
        "buffer_quantity",
        "on_hand"
      ]
    end

    def build_rows(sheet)
      skus.each do |sku|
        b = sku.inventory_balance

        sheet.add_row [
          sku.code,
          sku.brand,
          sku.model,
          sku.color,
          sku.size,
          sku.buffer_quantity.to_i,
          b&.on_hand.to_i
        ],
        types: [
          :string,
          :string,
          :string,
          :string,
          :string,
          :integer,
          :integer
        ]
      end
    end

    def set_column_widths(sheet)
      sheet.column_widths 40, 12, 25, 10, 8, 16, 12
    end
  end
end

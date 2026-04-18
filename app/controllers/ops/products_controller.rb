# frozen_string_literal: true

module Ops
  class ProductsController < BaseController
    def index
      @active_ops_nav = :products
    end

    def export_skus
      skus = Sku
        .includes(:inventory_balance)
        .order(:code)

      path = Rails.root.join("tmp", "exports", "skus", "skus_#{Time.now.to_i}.xlsx")
      FileUtils.mkdir_p(File.dirname(path))

      SkuExports::XlsxGenerator.call(
        skus: skus,
        output_path: path
      )

      send_file(
        path,
        filename: "sku_master_with_stock.xlsx",
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        disposition: "attachment"
      )
    end
  end
end

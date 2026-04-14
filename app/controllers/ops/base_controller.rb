# frozen_string_literal: true

module Ops
  class BaseController < ApplicationController
    layout "ops"

    private

    def ops_nav_items
      [
        { key: :products, label: "Product Management", path: "/ops/products" },
        { key: :orders, label: "Order Management", path: "/ops/orders_page" },
        { key: :returns, label: "Returns", path: "/ops/returns" },   # ✅ เพิ่มตรงนี้
        { key: :pos_cashier, label: "POS Cashier", path: "/ops/pos_cashier" },
        { key: :shopee, label: "Shopee Excel", path: "/ops/shopee" },
        { key: :marketplace_connections, label: "Marketplace Connections", path: "/ops/marketplace_connections" },
        { key: :barcode_bindings, label: "Barcode Binding", path: "/ops/barcode_bindings" },
        { key: :stock_sync, label: "Stock Sync Settings", path: "/ops/stock_sync_rollout_page" }
      ]
    end
    helper_method :ops_nav_items

    def active_ops_nav?(key)
      @active_ops_nav == key
    end
    helper_method :active_ops_nav?
  end
end

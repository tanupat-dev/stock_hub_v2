# frozen_string_literal: true

# Usage:
#   bin/rails runner script/test_shopee_import.rb path=tmp/shopee_orders.xlsx
#   bin/rails runner script/test_shopee_import.rb path="C:/Users/you/Desktop/shopee_orders.xlsx" shop_id=5
#
# Goal:
#   - import Shopee order Excel
#   - summarize FileBatch result
#   - show latest imported orders / lines / inventory actions (compact)
#
# Notes:
#   - safe for development/test
#   - does NOT print giant raw_payload blobs
#   - requires .xlsx input

require "pathname"

puts "\n=== SHOPEE IMPORT TEST START ==="

args = ARGV.each_with_object({}) do |arg, memo|
  k, v = arg.split("=", 2)
  memo[k] = v
end

filepath = args["path"].to_s
raise "missing path=... to Shopee Excel file" if filepath.blank?

fullpath = File.expand_path(filepath)
raise "file not found: #{fullpath}" unless File.exist?(fullpath)
raise "file must be .xlsx: #{fullpath}" unless File.extname(fullpath).downcase == ".xlsx"

shop =
  if args["shop_id"].present?
    Shop.find(args["shop_id"])
  else
    Shop.find_by!(channel: "shopee")
  end

puts "\n=== INPUT ==="
pp({
  shop: {
    id: shop.id,
    shop_code: shop.shop_code,
    channel: shop.channel,
    name: shop.name
  },
  file: {
    path: fullpath,
    filename: File.basename(fullpath),
    size_bytes: File.size(fullpath)
  }
})

before_batch_id = FileBatch.where(channel: "shopee", shop_id: shop.id, kind: "shopee_order_import").maximum(:id)
before_order_id = Order.where(channel: "shopee", shop_id: shop.id).maximum(:id)
before_line_id = OrderLine.joins(:order).where(orders: { channel: "shopee", shop_id: shop.id }).maximum(:id)

result = Shopee::ImportOrders.call!(
  shop: shop,
  filepath: fullpath,
  source_filename: File.basename(fullpath)
)

batch = FileBatch.find(result.fetch(:batch_id))

puts "\n=== IMPORT RESULT ==="
pp(result)

puts "\n=== BATCH SUMMARY ==="
pp({
  batch_id: batch.id,
  status: batch.status,
  source_filename: batch.source_filename,
  total_rows: batch.total_rows,
  success_rows: batch.success_rows,
  failed_rows: batch.failed_rows,
  started_at: batch.started_at,
  finished_at: batch.finished_at,
  meta: batch.meta,
  error_summary: batch.error_summary
})

new_orders_scope = Order.where(channel: "shopee", shop_id: shop.id)
new_orders_scope = new_orders_scope.where("id > ?", before_order_id) if before_order_id.present?
new_orders = new_orders_scope.order(id: :asc)

new_order_ids = new_orders.pluck(:id)

new_lines_scope = OrderLine.where(order_id: new_order_ids)
new_lines_scope = new_lines_scope.where("id > ?", before_line_id) if before_line_id.present?
new_lines = new_lines_scope.order(:id)

new_line_ids = new_lines.pluck(:id)

new_actions = InventoryAction.where(order_line_id: new_line_ids).order(:id)

puts "\n=== NEW RECORD COUNTS ==="
pp({
  new_orders_count: new_orders.count,
  new_order_lines_count: new_lines.count,
  new_inventory_actions_count: new_actions.count
})

puts "\n=== LATEST IMPORTED ORDERS (max 10) ==="
new_orders.limit(10).each do |order|
  puts({
    id: order.id,
    external_order_id: order.external_order_id,
    status: order.status,
    buyer_name: order.buyer_name,
    province: order.province,
    updated_at_external: order.updated_at_external
  })
end

puts "\n=== ORDER LINES (max 20) ==="
new_lines.limit(20).pluck(
  :id,
  :order_id,
  :external_line_id,
  :external_sku,
  :sku_id,
  :quantity,
  :status
).each do |row|
  p row
end

puts "\n=== INVENTORY ACTIONS (max 30) ==="
new_actions.limit(30).pluck(
  :id,
  :order_line_id,
  :sku_id,
  :action_type,
  :quantity,
  :idempotency_key
).each do |row|
  p row
end

puts "\n=== UNKNOWN STATUSES ==="
pp(batch.meta["unknown_statuses"] || {})

puts "\n=== SHOPEE IMPORT TEST DONE ==="

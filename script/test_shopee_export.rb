# frozen_string_literal: true

# Usage:
#   bin/rails runner script/test_shopee_export.rb template=tmp/shopee_stock_template.xlsx
#   bin/rails runner script/test_shopee_export.rb template="C:/Users/you/Desktop/shopee_template.xlsx" shop_id=5 out=tmp/shopee_stock_out.xlsx
#
# Goal:
#   - export Shopee stock into Excel template
#   - modify only column I via service
#   - print FileBatch summary
#
# Notes:
#   - requires .xlsx template
#   - output defaults to tmp/shopee_stock_export_<timestamp>.xlsx

require "fileutils"

puts "\n=== SHOPEE EXPORT TEST START ==="

args = ARGV.each_with_object({}) do |arg, memo|
  k, v = arg.split("=", 2)
  memo[k] = v
end

template_path = args["template"].to_s
raise "missing template=... to Shopee Excel template" if template_path.blank?

template_fullpath = File.expand_path(template_path)
raise "template file not found: #{template_fullpath}" unless File.exist?(template_fullpath)
raise "template file must be .xlsx: #{template_fullpath}" unless File.extname(template_fullpath).downcase == ".xlsx"

shop =
  if args["shop_id"].present?
    Shop.find(args["shop_id"])
  else
    Shop.find_by!(channel: "shopee")
  end

default_output = Rails.root.join("tmp", "shopee_stock_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xlsx").to_s
output_path = args["out"].presence || default_output
output_fullpath = File.expand_path(output_path)

FileUtils.mkdir_p(File.dirname(output_fullpath))

puts "\n=== INPUT ==="
pp({
  shop: {
    id: shop.id,
    shop_code: shop.shop_code,
    channel: shop.channel,
    name: shop.name
  },
  template: {
    path: template_fullpath,
    filename: File.basename(template_fullpath),
    size_bytes: File.size(template_fullpath)
  },
  output: output_fullpath
})

result = Shopee::ExportStockExcel.call!(
  shop: shop,
  template_path: template_fullpath,
  output_path: output_fullpath
)

batch = FileBatch.find(result.fetch(:batch_id))

puts "\n=== EXPORT RESULT ==="
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

puts "\n=== OUTPUT FILE ==="
pp({
  path: output_fullpath,
  exists: File.exist?(output_fullpath),
  size_bytes: (File.exist?(output_fullpath) ? File.size(output_fullpath) : nil)
})

puts "\n=== SHOPEE EXPORT TEST DONE ==="

# frozen_string_literal: true

# Usage:
#   bin/rails runner script/test_bind_barcode.rb sku_code="Walker.M3310.ดำ.47" barcode="8851234567890"
#   bin/rails runner script/test_bind_barcode.rb sku_id=4604 barcode="8851234567890"
#   bin/rails runner script/test_bind_barcode.rb sku_code="Walker.M3310.ดำ.47" barcode="8851234567890" force=true
#
# Also supports ENV style:
#   sku_id=4604 barcode="8851234567890" bin/rails runner script/test_bind_barcode.rb

puts "\n=== BIND BARCODE TEST START ==="

argv_params = ARGV.each_with_object({}) do |arg, h|
  k, v = arg.to_s.split("=", 2)
  next if k.blank?
  h[k] = v
end

sku_id   = argv_params["sku_id"].presence || ENV["sku_id"].presence
sku_code = argv_params["sku_code"].presence || ENV["sku_code"].presence
barcode  = argv_params["barcode"].presence || ENV["barcode"].presence
force_raw = argv_params["force"].presence || ENV["force"].presence

sku =
  if sku_id.present?
    Sku.find(sku_id)
  elsif sku_code.present?
    Sku.find_by!(code: sku_code)
  else
    raise "provide sku_id=... or sku_code=..."
  end

raise "provide barcode=..." if barcode.blank?

force = ActiveModel::Type::Boolean.new.cast(force_raw)

puts "\n=== INPUT ==="
pp({
  sku: {
    id: sku.id,
    code: sku.code,
    barcode: sku.barcode
  },
  requested_barcode: barcode,
  force: force
})

before = {
  id: sku.id,
  code: sku.code,
  barcode: sku.barcode
}

result = Inventory::BindBarcode.call!(
  sku: sku,
  barcode: barcode,
  force: force,
  meta: { source: "script/test_bind_barcode" }
)

sku.reload

puts "\n=== RESULT ==="
pp({
  result: result,
  before: before,
  after: {
    id: sku.id,
    code: sku.code,
    barcode: sku.barcode
  }
})

puts "\n=== BIND BARCODE TEST DONE ==="

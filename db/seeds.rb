shops = [
  { channel: "tiktok", shop_code: "tiktok_1", name: "TikTok Shop 1" },
  { channel: "tiktok", shop_code: "tiktok_2", name: "TikTok Shop 2" },
  { channel: "lazada", shop_code: "lazada_1", name: "Lazada 1" },
  { channel: "lazada", shop_code: "lazada_2", name: "Lazada 2" },
  { channel: "shopee", shop_code: "shopee_1", name: "Shopee 1" }
]

shops.each do |attrs|
  Shop.find_or_create_by!(channel: attrs[:channel], shop_code: attrs[:shop_code]) do |shop|
    shop.name = attrs[:name]
    shop.active = true
  end
end

sku1 = Sku.find_or_create_by!(code: "WALKER-001") do |s|
  s.barcode = "885000000001"
  s.brand = "Walker"
  s.model = "Boston"
  s.color = "black"
  s.size = "42"
  s.buffer_quantity = 3
end

sku2 = Sku.find_or_create_by!(code: "ADDA-001") do |s|
  s.barcode = "885000000002"
  s.brand = "Adda"
  s.model = "41C21"
  s.color = "black"
  s.size = "32"
  s.buffer_quantity = 3
end

[sku1, sku2].each do |sku|
  sku.inventory_balance || sku.create_inventory_balance!(on_hand: 10, reserved: 0)
end
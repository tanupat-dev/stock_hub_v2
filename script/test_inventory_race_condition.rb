# frozen_string_literal: true

# Usage:
# bin/rails runner script/test_inventory_race_condition.rb

puts "\n=== INVENTORY RACE CONDITION TEST ==="

sku = Sku.find_by!(code: "Walker.M3310.ดำ.47")

THREADS = 20
RESERVE_QTY = 1

Inventory::Adjust.call!(
  sku: sku,
  set_to: 5,
  idempotency_key: "race_test_adjust",
  meta: { source: "race_test" }
)

sku.inventory_balance.update!(reserved: 0)

puts "\nInitial state"
pp({
  on_hand: sku.inventory_balance.on_hand,
  reserved: sku.inventory_balance.reserved
})

threads = []

THREADS.times do |i|
  threads << Thread.new do
    begin
      Inventory::Reserve.call!(
        sku: sku,
        quantity: RESERVE_QTY,
        idempotency_key: "race_test_reserve_#{i}",
        meta: { thread: i }
      )
    rescue => e
      puts "thread #{i} error: #{e.class}"
    end
  end
end

threads.each(&:join)

sku.reload
balance = sku.inventory_balance.reload

puts "\n=== FINAL STATE ==="
pp({
  on_hand: balance.on_hand,
  reserved: balance.reserved,
  raw_available: balance.on_hand - balance.reserved
})

actions = InventoryAction
  .where("idempotency_key LIKE ?", "race_test_reserve_%")
  .pluck(:action_type)

puts "\n=== ACTION COUNT ==="
pp({
  successful_reserve_actions: actions.count
})

puts "\n=== TEST RESULT ==="

if balance.reserved <= balance.on_hand
  puts "PASS: no oversell"
else
  puts "FAIL: oversell occurred"
end

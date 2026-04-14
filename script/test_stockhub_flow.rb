# frozen_string_literal: true

# Usage:
#   bin/rails runner script/test_stockhub_flow.rb
#
# Goal:
#   End-to-end sanity test for StockHub core flow:
#   - inventory reserve / commit / release
#   - debounce stock sync request
#   - debounced sync job execution
#   - shop mapping / marketplace item visibility
#
# Notes:
#   - Safe for development/test data only
#   - Uses dedicated idempotency keys and test orders
#   - Cleans up only the test orders it creates
#   - Does NOT require SolidQueue worker on Windows
#   - Executes DebouncedSyncStockJob.perform_now manually

puts "\n=== STOCKHUB FLOW TEST START ==="

shop = Shop.find_by!(channel: "lazada", shop_code: "lazada_1")
sku  = Sku.find_by!(code: "Walker.M3310.ดำ.47")

mapping = SkuMapping.find_by!(
  channel: "lazada",
  shop_id: shop.id,
  external_sku: sku.code
)

item = MarketplaceItem.find_by!(
  shop_id: shop.id,
  external_variant_id: mapping.external_variant_id
)

puts "\n=== PRECHECK ==="
pp({
  shop: {
    id: shop.id,
    shop_code: shop.shop_code,
    channel: shop.channel
  },
  sku: {
    id: sku.id,
    code: sku.code,
    buffer_quantity: sku.buffer_quantity
  },
  mapping: {
    id: mapping.id,
    external_sku: mapping.external_sku,
    external_variant_id: mapping.external_variant_id
  },
  marketplace_item: {
    id: item.id,
    status: item.status,
    available_stock: item.available_stock
  }
})

# ------------------------------------------------------------
# Cleanup old test orders
# ------------------------------------------------------------
test_order_ids = [
  "TEST-FLOW-RESERVE",
  "TEST-FLOW-COMMIT",
  "TEST-FLOW-RELEASE"
]

orders = Order.where(
  channel: "lazada",
  shop_id: shop.id,
  external_order_id: test_order_ids
).includes(:order_lines)

line_ids = orders.flat_map { |o| o.order_lines.pluck(:id) }

InventoryAction.where(order_line_id: line_ids).delete_all

InventoryAction.where(
  "idempotency_key LIKE ? OR idempotency_key LIKE ? OR idempotency_key LIKE ? OR idempotency_key LIKE ?",
  "test:flow:%",
  "lazada:order:TEST-FLOW-RESERVE:%",
  "lazada:order:TEST-FLOW-COMMIT:%",
  "lazada:order:TEST-FLOW-RELEASE:%"
).delete_all

OrderLine.where(id: line_ids).delete_all
orders.delete_all

StockSyncRequest.where(sku_id: sku.id).delete_all

balance = sku.inventory_balance || sku.create_inventory_balance!(on_hand: 0, reserved: 0)

# ------------------------------------------------------------
# Seed stock to predictable state
# ------------------------------------------------------------
Inventory::Adjust.call!(
  sku: sku,
  set_to: 5,
  idempotency_key: "test:flow:adjust_on_hand_to_5",
  meta: { source: "script/test_stockhub_flow" }
)

balance.reload
if balance.reserved.to_i > 0
  Inventory::Release.call!(
    sku: sku,
    quantity: balance.reserved.to_i,
    idempotency_key: "test:flow:release_existing_reserved",
    meta: { source: "script/test_stockhub_flow" }
  )
end

sku.reload
balance = sku.inventory_balance.reload

puts "\n=== AFTER RESET ==="
pp({
  balance: {
    on_hand: balance.on_hand,
    reserved: balance.reserved,
    frozen_at: balance.frozen_at,
    freeze_reason: balance.freeze_reason
  },
  availability: {
    store_available: sku.store_available,
    online_available: sku.online_available
  }
})

# ------------------------------------------------------------
# 1) RESERVE FLOW
# ------------------------------------------------------------
reserve_order = Orders::Lazada::Upsert.call!(
  shop: shop,
  raw_order: {
    "id" => "TEST-FLOW-RESERVE",
    "status" => "AWAITING_SHIPMENT",
    "update_time" => Time.current.to_i,
    "buyer_name" => "reserve test",
    "province" => "Bangkok",
    "buyer_note" => "script reserve test",
    "line_items" => [
      {
        "id" => "TEST-FLOW-RESERVE-LINE-1",
        "seller_sku" => sku.code,
        "quantity" => 1,
        "display_status" => "confirmed"
      }
    ]
  }
)

# ------------------------------------------------------------
# 2) COMMIT FLOW
# ------------------------------------------------------------
commit_order = Orders::Lazada::Upsert.call!(
  shop: shop,
  raw_order: {
    "id" => "TEST-FLOW-COMMIT",
    "status" => "IN_TRANSIT",
    "update_time" => Time.current.to_i,
    "buyer_name" => "commit test",
    "province" => "Bangkok",
    "buyer_note" => "script commit test",
    "line_items" => [
      {
        "id" => "TEST-FLOW-COMMIT-LINE-1",
        "seller_sku" => sku.code,
        "quantity" => 1,
        "display_status" => "shipped"
      }
    ]
  }
)

# ------------------------------------------------------------
# 3) RELEASE FLOW
# ------------------------------------------------------------
release_order = Orders::Lazada::Upsert.call!(
  shop: shop,
  raw_order: {
    "id" => "TEST-FLOW-RELEASE",
    "status" => "CANCELLED",
    "update_time" => Time.current.to_i,
    "buyer_name" => "release test",
    "province" => "Bangkok",
    "buyer_note" => "script release test",
    "line_items" => [
      {
        "id" => "TEST-FLOW-RELEASE-LINE-1",
        "seller_sku" => sku.code,
        "quantity" => 1,
        "display_status" => "cancelled"
      }
    ]
  }
)

sku.reload
balance = sku.inventory_balance.reload

puts "\n=== AFTER ORDER POLICY FLOWS ==="
pp({
  reserve_order: {
    id: reserve_order.id,
    external_order_id: reserve_order.external_order_id,
    status: reserve_order.status
  },
  commit_order: {
    id: commit_order.id,
    external_order_id: commit_order.external_order_id,
    status: commit_order.status
  },
  release_order: {
    id: release_order.id,
    external_order_id: release_order.external_order_id,
    status: release_order.status
  },
  balance: {
    on_hand: balance.on_hand,
    reserved: balance.reserved,
    frozen_at: balance.frozen_at,
    freeze_reason: balance.freeze_reason
  },
  availability: {
    store_available: sku.store_available,
    online_available: sku.online_available
  }
})

# ------------------------------------------------------------
# Check actions
# Expected:
# - TEST-FLOW-RESERVE => reserve
# - TEST-FLOW-COMMIT  => reserve_for_commit + commit
# - TEST-FLOW-RELEASE => release
# ------------------------------------------------------------
orders = Order.where(
  channel: "lazada",
  shop_id: shop.id,
  external_order_id: test_order_ids
).includes(:order_lines)

line_ids = orders.flat_map { |o| o.order_lines.pluck(:id) }

actions = InventoryAction.where(order_line_id: line_ids)
                         .order(:id)
                         .pluck(:order_line_id, :sku_id, :action_type, :quantity, :idempotency_key)

puts "\n=== INVENTORY ACTIONS ==="
pp(actions)

# ------------------------------------------------------------
# 4) DEBOUNCE FLOW
# ------------------------------------------------------------
StockSyncRequest.where(sku_id: sku.id).delete_all

Inventory::Reserve.call!(
  sku: sku,
  quantity: 1,
  idempotency_key: "test:flow:debounce_reserve",
  meta: { source: "script/test_stockhub_flow" }
)

StockSync::RequestDebouncer.call!(
  sku: sku,
  reason: "script_test"
)

req = StockSyncRequest.find_by!(sku_id: sku.id)

puts "\n=== DEBOUNCE REQUEST CREATED ==="
pp({
  stock_sync_request: req.attributes.slice(
    "sku_id",
    "status",
    "last_reason",
    "scheduled_for",
    "last_enqueued_at",
    "last_processed_at",
    "last_error"
  )
})

scheduled_jobs = SolidQueue::ScheduledExecution
  .joins("INNER JOIN solid_queue_jobs ON solid_queue_jobs.id = solid_queue_scheduled_executions.job_id")
  .where("solid_queue_jobs.class_name = ?", "DebouncedSyncStockJob")
  .pluck("solid_queue_jobs.id", "solid_queue_scheduled_executions.queue_name", "solid_queue_scheduled_executions.scheduled_at")

puts "\n=== SCHEDULED DEBOUNCED JOBS ==="
pp(scheduled_jobs)

# ------------------------------------------------------------
# 5) RUN DEBOUNCED JOB MANUALLY (DEV/WINDOWS SAFE)
# ------------------------------------------------------------
req.update!(
  scheduled_for: 1.minute.ago,
  last_enqueued_at: Time.current,
  status: "pending",
  last_error: nil
)

debounced_result = DebouncedSyncStockJob.perform_now(sku.id)

req.reload

puts "\n=== DEBOUNCED JOB RESULT ==="
pp({
  debounced_result: debounced_result,
  stock_sync_request_after: req.attributes.slice(
    "sku_id",
    "status",
    "last_reason",
    "scheduled_for",
    "last_enqueued_at",
    "last_processed_at",
    "last_error"
  )
})

# ------------------------------------------------------------
# 6) FINAL SUMMARY
# ------------------------------------------------------------
sku.reload
balance = sku.inventory_balance.reload
state = ShopSkuSyncState.find_by(shop_id: shop.id, sku_id: sku.id)

puts "\n=== FINAL SUMMARY ==="
pp({
  sku: {
    id: sku.id,
    code: sku.code
  },
  balance: {
    on_hand: balance.on_hand,
    reserved: balance.reserved,
    frozen_at: balance.frozen_at,
    freeze_reason: balance.freeze_reason
  },
  availability: {
    store_available: sku.store_available,
    online_available: sku.online_available
  },
  shop_sku_sync_state: state && {
    last_pushed_available: state.last_pushed_available,
    last_pushed_at: state.last_pushed_at,
    fail_count: state.fail_count,
    last_failed_at: state.last_failed_at,
    last_error: state.last_error
  }
})

puts "\n=== STOCKHUB FLOW TEST DONE ==="

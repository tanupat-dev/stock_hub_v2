# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_01_123000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "file_batches", force: :cascade do |t|
    t.string "channel", null: false
    t.bigint "shop_id", null: false
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "source_filename"
    t.integer "total_rows", default: 0, null: false
    t.integer "success_rows", default: 0, null: false
    t.integer "failed_rows", default: 0, null: false
    t.jsonb "meta", default: {}, null: false
    t.text "error_summary"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel", "shop_id", "kind"], name: "index_file_batches_on_channel_and_shop_id_and_kind"
    t.index ["created_at"], name: "index_file_batches_on_created_at"
    t.index ["status"], name: "index_file_batches_on_status"
  end

  create_table "inventory_actions", force: :cascade do |t|
    t.bigint "sku_id", null: false
    t.bigint "order_line_id"
    t.string "action_type", null: false
    t.integer "quantity", default: 1, null: false
    t.string "idempotency_key", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_inventory_actions_on_idempotency_key", unique: true
    t.index ["order_line_id"], name: "index_inventory_actions_on_order_line_id"
    t.index ["sku_id", "created_at"], name: "index_inventory_actions_on_sku_id_and_created_at"
    t.index ["sku_id"], name: "index_inventory_actions_on_sku_id"
    t.check_constraint "quantity > 0", name: "chk_inventory_action_qty_positive"
  end

  create_table "inventory_balances", force: :cascade do |t|
    t.bigint "sku_id", null: false
    t.integer "on_hand", default: 0, null: false
    t.integer "reserved", default: 0, null: false
    t.string "freeze_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "frozen_at"
    t.integer "last_pushed_available"
    t.datetime "last_pushed_at"
    t.bigint "stock_identity_id"
    t.index ["frozen_at"], name: "index_inventory_balances_on_frozen_at"
    t.index ["sku_id"], name: "index_inventory_balances_on_sku_id", unique: true
    t.index ["stock_identity_id"], name: "index_inventory_balances_on_stock_identity_id", unique: true
    t.check_constraint "on_hand >= 0", name: "chk_on_hand_non_negative"
    t.check_constraint "reserved >= 0", name: "chk_reserved_non_negative"
  end

  create_table "inventory_reconcile_runs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.integer "mismatched_count", default: 0, null: false
    t.integer "unmapped_count", default: 0, null: false
    t.integer "pushed_count", default: 0, null: false
    t.text "error"
    t.datetime "ran_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ran_at"], name: "index_inventory_reconcile_runs_on_ran_at"
    t.index ["shop_id", "ran_at"], name: "index_inventory_reconcile_runs_on_shop_and_ran_at"
    t.index ["shop_id"], name: "index_inventory_reconcile_runs_on_shop_id"
  end

  create_table "lazada_apps", force: :cascade do |t|
    t.string "code", null: false
    t.string "app_key", null: false
    t.string "app_secret", null: false
    t.string "auth_host", default: "https://auth.lazada.com", null: false
    t.string "api_host", default: "https://api.lazada.co.th", null: false
    t.string "callback_url"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_lazada_apps_on_active"
    t.index ["code"], name: "index_lazada_apps_on_code", unique: true
  end

  create_table "lazada_credentials", force: :cascade do |t|
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "refresh_expires_at"
    t.string "account"
    t.string "account_platform"
    t.string "country"
    t.string "seller_id"
    t.string "user_id"
    t.string "short_code"
    t.jsonb "raw_payload", default: {}, null: false
    t.bigint "lazada_app_id"
    t.index ["lazada_app_id"], name: "index_lazada_credentials_on_lazada_app_id"
    t.index ["seller_id"], name: "index_lazada_credentials_on_seller_id"
    t.index ["short_code"], name: "index_lazada_credentials_on_short_code"
  end

  create_table "marketplace_items", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "channel", null: false
    t.string "external_product_id"
    t.string "external_variant_id"
    t.string "external_sku"
    t.string "title"
    t.string "status"
    t.integer "available_stock", default: 0, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "external_sku"], name: "index_marketplace_items_on_sku", where: "(external_sku IS NOT NULL)"
    t.index ["shop_id", "external_variant_id"], name: "uniq_marketplace_variant", unique: true, where: "(external_variant_id IS NOT NULL)"
    t.index ["shop_id"], name: "index_marketplace_items_on_shop_id"
  end

  create_table "order_lines", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "external_line_id"
    t.string "external_sku"
    t.bigint "sku_id"
    t.integer "quantity", default: 1, null: false
    t.string "status"
    t.string "idempotency_key", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_order_lines_on_idempotency_key", unique: true
    t.index ["order_id", "external_line_id"], name: "uniq_order_lines_when_external_line", unique: true, where: "(external_line_id IS NOT NULL)"
    t.index ["order_id"], name: "index_order_lines_on_order_id"
    t.index ["sku_id"], name: "index_order_lines_on_sku_id"
    t.check_constraint "quantity > 0", name: "chk_order_line_qty_positive"
  end

  create_table "orders", force: :cascade do |t|
    t.string "channel", null: false
    t.bigint "shop_id", null: false
    t.string "external_order_id", null: false
    t.string "status", null: false
    t.string "buyer_name"
    t.string "province"
    t.text "buyer_note"
    t.bigint "updated_time_external"
    t.datetime "updated_at_external"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel", "shop_id", "external_order_id"], name: "uniq_orders_channel_shop_external", unique: true
    t.index ["channel", "status"], name: "index_orders_on_channel_and_status"
    t.index ["shop_id", "updated_time_external"], name: "index_orders_on_shop_id_and_updated_time_external"
    t.index ["shop_id"], name: "index_orders_on_shop_id"
  end

  create_table "oversell_allocations", force: :cascade do |t|
    t.bigint "oversell_incident_id", null: false
    t.bigint "order_line_id", null: false
    t.bigint "sku_id", null: false
    t.integer "quantity", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_line_id"], name: "index_oversell_allocations_on_order_line_id"
    t.index ["oversell_incident_id", "order_line_id"], name: "uniq_oversell_alloc_incident_line", unique: true
    t.index ["oversell_incident_id"], name: "index_oversell_allocations_on_oversell_incident_id"
    t.index ["sku_id", "order_line_id"], name: "index_oversell_allocations_on_sku_id_and_order_line_id"
    t.index ["sku_id"], name: "index_oversell_allocations_on_sku_id"
    t.check_constraint "quantity > 0", name: "chk_oversell_alloc_qty_positive"
  end

  create_table "oversell_incidents", force: :cascade do |t|
    t.bigint "sku_id", null: false
    t.integer "shortfall_qty", null: false
    t.string "trigger", null: false
    t.string "status", default: "open", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "idempotency_key", default: "", null: false
    t.index ["idempotency_key"], name: "index_oversell_incidents_on_idempotency_key", unique: true
    t.index ["sku_id", "status"], name: "index_oversell_incidents_on_sku_id_and_status"
    t.index ["sku_id"], name: "index_oversell_incidents_on_sku_id"
    t.check_constraint "shortfall_qty > 0", name: "chk_oversell_incident_shortfall_positive"
  end

  create_table "pos_exchanges", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "pos_sale_id", null: false
    t.bigint "pos_return_id"
    t.bigint "new_pos_sale_id"
    t.string "exchange_number", null: false
    t.string "status", default: "open", null: false
    t.string "idempotency_key", null: false
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exchange_number"], name: "index_pos_exchanges_on_exchange_number", unique: true
    t.index ["idempotency_key"], name: "index_pos_exchanges_on_idempotency_key", unique: true
    t.index ["new_pos_sale_id"], name: "index_pos_exchanges_on_new_pos_sale_id"
    t.index ["pos_return_id"], name: "index_pos_exchanges_on_pos_return_id"
    t.index ["pos_sale_id", "created_at"], name: "index_pos_exchanges_on_pos_sale_id_and_created_at"
    t.index ["pos_sale_id"], name: "index_pos_exchanges_on_pos_sale_id"
    t.index ["shop_id", "created_at"], name: "index_pos_exchanges_on_shop_id_and_created_at"
    t.index ["shop_id"], name: "index_pos_exchanges_on_shop_id"
    t.index ["status"], name: "index_pos_exchanges_on_status"
  end

  create_table "pos_return_lines", force: :cascade do |t|
    t.bigint "pos_return_id", null: false
    t.bigint "pos_sale_line_id", null: false
    t.bigint "sku_id", null: false
    t.integer "quantity", null: false
    t.string "barcode_snapshot"
    t.string "sku_code_snapshot", null: false
    t.string "idempotency_key", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_pos_return_lines_on_idempotency_key", unique: true
    t.index ["pos_return_id", "sku_id"], name: "index_pos_return_lines_on_pos_return_id_and_sku_id"
    t.index ["pos_return_id"], name: "index_pos_return_lines_on_pos_return_id"
    t.index ["pos_sale_line_id", "created_at"], name: "index_pos_return_lines_on_pos_sale_line_id_and_created_at"
    t.index ["pos_sale_line_id"], name: "index_pos_return_lines_on_pos_sale_line_id"
    t.index ["sku_id"], name: "index_pos_return_lines_on_sku_id"
    t.check_constraint "quantity > 0", name: "chk_pos_return_lines_quantity_positive"
  end

  create_table "pos_returns", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "pos_sale_id", null: false
    t.string "return_number", null: false
    t.string "status", default: "open", null: false
    t.string "idempotency_key", null: false
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_pos_returns_on_idempotency_key", unique: true
    t.index ["pos_sale_id", "created_at"], name: "index_pos_returns_on_pos_sale_id_and_created_at"
    t.index ["pos_sale_id"], name: "index_pos_returns_on_pos_sale_id"
    t.index ["return_number"], name: "index_pos_returns_on_return_number", unique: true
    t.index ["shop_id", "created_at"], name: "index_pos_returns_on_shop_id_and_created_at"
    t.index ["shop_id"], name: "index_pos_returns_on_shop_id"
    t.index ["status"], name: "index_pos_returns_on_status"
  end

  create_table "pos_sale_lines", force: :cascade do |t|
    t.bigint "pos_sale_id", null: false
    t.bigint "sku_id", null: false
    t.string "status", default: "active", null: false
    t.string "barcode_snapshot"
    t.string "sku_code_snapshot", null: false
    t.string "title_snapshot"
    t.integer "quantity", default: 1, null: false
    t.string "idempotency_key", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_pos_sale_lines_on_idempotency_key", unique: true
    t.index ["pos_sale_id", "created_at"], name: "index_pos_sale_lines_on_pos_sale_id_and_created_at"
    t.index ["pos_sale_id", "sku_id"], name: "index_pos_sale_lines_on_pos_sale_id_and_sku_id"
    t.index ["pos_sale_id"], name: "index_pos_sale_lines_on_pos_sale_id"
    t.index ["sku_id"], name: "index_pos_sale_lines_on_sku_id"
    t.index ["status"], name: "index_pos_sale_lines_on_status"
    t.check_constraint "quantity > 0", name: "chk_pos_sale_lines_quantity_positive"
  end

  create_table "pos_sales", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "sale_number", null: false
    t.string "status", default: "cart", null: false
    t.integer "item_count", default: 0, null: false
    t.string "idempotency_key", null: false
    t.datetime "checked_out_at"
    t.datetime "voided_at"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_out_at"], name: "index_pos_sales_on_checked_out_at"
    t.index ["idempotency_key"], name: "index_pos_sales_on_idempotency_key", unique: true
    t.index ["sale_number"], name: "index_pos_sales_on_sale_number", unique: true
    t.index ["shop_id", "created_at"], name: "index_pos_sales_on_shop_id_and_created_at"
    t.index ["shop_id", "status", "created_at"], name: "index_pos_sales_on_shop_id_and_status_and_created_at"
    t.index ["shop_id"], name: "index_pos_sales_on_shop_id"
    t.index ["status"], name: "index_pos_sales_on_status"
    t.index ["voided_at"], name: "index_pos_sales_on_voided_at"
    t.check_constraint "item_count >= 0", name: "chk_pos_sales_item_count_non_negative"
  end

  create_table "return_scans", force: :cascade do |t|
    t.bigint "return_shipment_id", null: false
    t.bigint "order_line_id", null: false
    t.bigint "sku_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "idempotency_key", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "scanned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_return_scans_on_idempotency_key", unique: true
    t.index ["return_shipment_id", "order_line_id"], name: "index_return_scans_on_return_shipment_id_and_order_line_id"
    t.index ["scanned_at"], name: "index_return_scans_on_scanned_at"
    t.index ["sku_id"], name: "index_return_scans_on_sku_id"
    t.check_constraint "quantity > 0", name: "chk_return_scans_qty_positive"
  end

  create_table "return_shipment_lines", force: :cascade do |t|
    t.bigint "return_shipment_id", null: false
    t.bigint "order_line_id"
    t.bigint "sku_id"
    t.string "external_line_id"
    t.string "sku_code_snapshot", null: false
    t.integer "qty_returned", default: 1, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_line_id"], name: "index_return_shipment_lines_on_order_line_id"
    t.index ["return_shipment_id", "external_line_id"], name: "uniq_return_shipment_lines_external_line", unique: true, where: "(external_line_id IS NOT NULL)"
    t.index ["return_shipment_id", "order_line_id", "sku_code_snapshot"], name: "idx_return_shipment_lines_lookup"
    t.index ["return_shipment_id"], name: "index_return_shipment_lines_on_return_shipment_id"
    t.index ["sku_code_snapshot"], name: "index_return_shipment_lines_on_sku_code_snapshot"
    t.index ["sku_id"], name: "index_return_shipment_lines_on_sku_id"
    t.check_constraint "qty_returned > 0", name: "chk_return_shipment_lines_qty_positive"
  end

  create_table "return_shipments", force: :cascade do |t|
    t.string "channel", null: false
    t.bigint "shop_id", null: false
    t.bigint "order_id"
    t.string "external_return_id"
    t.string "tracking_number"
    t.string "external_order_id", null: false
    t.string "status_marketplace"
    t.string "status_store", default: "pending_scan", null: false
    t.datetime "last_seen_at_external"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "requested_at"
    t.string "return_carrier_method"
    t.string "return_delivery_status"
    t.datetime "returned_delivered_at"
    t.string "buyer_username"
    t.jsonb "raw_payload", default: {}, null: false
    t.index ["channel", "shop_id", "external_order_id"], name: "idx_return_shipments_order_lookup"
    t.index ["channel", "shop_id", "external_return_id"], name: "uniq_return_shipments_by_external_return", unique: true, where: "(external_return_id IS NOT NULL)"
    t.index ["external_return_id"], name: "index_return_shipments_on_external_return_id"
    t.index ["requested_at"], name: "index_return_shipments_on_requested_at"
    t.index ["returned_delivered_at"], name: "index_return_shipments_on_returned_delivered_at"
    t.index ["status_marketplace"], name: "index_return_shipments_on_status_marketplace"
    t.index ["status_store"], name: "index_return_shipments_on_status_store"
    t.index ["tracking_number"], name: "index_return_shipments_on_tracking_number"
  end

  create_table "shipping_export_batch_items", force: :cascade do |t|
    t.bigint "shipping_export_batch_id", null: false
    t.bigint "order_id", null: false
    t.string "channel", null: false
    t.bigint "shop_id", null: false
    t.string "external_order_id", null: false
    t.string "order_status_snapshot"
    t.datetime "exported_at"
    t.integer "row_index"
    t.jsonb "payload_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_shipping_export_batch_items_on_channel"
    t.index ["external_order_id"], name: "index_shipping_export_batch_items_on_external_order_id"
    t.index ["order_id"], name: "index_shipping_export_batch_items_on_order_id"
    t.index ["shipping_export_batch_id", "order_id"], name: "idx_ship_export_batch_items_batch_order", unique: true
    t.index ["shipping_export_batch_id"], name: "index_shipping_export_batch_items_on_shipping_export_batch_id"
    t.index ["shop_id"], name: "index_shipping_export_batch_items_on_shop_id"
  end

  create_table "shipping_export_batches", force: :cascade do |t|
    t.string "export_key", null: false
    t.string "status", default: "building", null: false
    t.string "template_name", null: false
    t.jsonb "filters_snapshot", default: {}, null: false
    t.integer "row_count", default: 0, null: false
    t.string "file_path"
    t.datetime "requested_at", null: false
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.text "error_message"
    t.jsonb "debug_meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["export_key"], name: "index_shipping_export_batches_on_export_key", unique: true
    t.index ["requested_at"], name: "index_shipping_export_batches_on_requested_at"
    t.index ["status"], name: "index_shipping_export_batches_on_status"
  end

  create_table "shop_sku_sync_states", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "sku_id", null: false
    t.integer "last_pushed_available"
    t.datetime "last_pushed_at"
    t.integer "fail_count", default: 0, null: false
    t.datetime "last_failed_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_pushed_at"], name: "index_shop_sku_sync_states_on_last_pushed_at"
    t.index ["shop_id", "sku_id"], name: "index_shop_sku_sync_states_on_shop_id_and_sku_id", unique: true
    t.index ["shop_id"], name: "index_shop_sku_sync_states_on_shop_id"
    t.index ["sku_id"], name: "index_shop_sku_sync_states_on_sku_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "channel", null: false
    t.string "shop_code", null: false
    t.string "name"
    t.bigint "last_seen_update_time"
    t.datetime "last_polled_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sync_fail_count", default: 0, null: false
    t.datetime "last_sync_failed_at"
    t.text "last_sync_error"
    t.string "external_shop_id"
    t.string "shop_cipher"
    t.string "region"
    t.string "seller_type"
    t.bigint "tiktok_credential_id"
    t.string "catalog_last_page_token"
    t.datetime "catalog_last_polled_at"
    t.integer "catalog_last_total_count"
    t.text "catalog_last_error"
    t.integer "catalog_fail_count", default: 0, null: false
    t.bigint "lazada_credential_id"
    t.bigint "lazada_app_id"
    t.bigint "tiktok_app_id"
    t.bigint "tiktok_returns_last_seen_update_time"
    t.datetime "tiktok_returns_last_polled_at"
    t.bigint "lazada_returns_last_seen_update_time"
    t.datetime "lazada_returns_last_polled_at"
    t.boolean "stock_sync_enabled", default: false, null: false
    t.bigint "lazada_orders_last_seen_update_time"
    t.datetime "lazada_orders_last_polled_at"
    t.index ["catalog_last_polled_at"], name: "index_shops_on_catalog_last_polled_at"
    t.index ["channel", "active"], name: "index_shops_on_channel_and_active"
    t.index ["channel", "shop_code"], name: "index_shops_on_channel_and_shop_code", unique: true
    t.index ["external_shop_id"], name: "index_shops_on_external_shop_id"
    t.index ["lazada_app_id"], name: "index_shops_on_lazada_app_id"
    t.index ["lazada_credential_id"], name: "index_shops_on_lazada_credential_id"
    t.index ["lazada_orders_last_polled_at"], name: "idx_shops_lazada_orders_polled_at"
    t.index ["lazada_orders_last_seen_update_time"], name: "idx_shops_lazada_orders_cursor"
    t.index ["lazada_returns_last_polled_at"], name: "index_shops_on_lazada_returns_last_polled_at"
    t.index ["lazada_returns_last_seen_update_time"], name: "index_shops_on_lazada_returns_last_seen_update_time"
    t.index ["shop_cipher"], name: "index_shops_on_shop_cipher"
    t.index ["stock_sync_enabled"], name: "index_shops_on_stock_sync_enabled"
    t.index ["tiktok_app_id"], name: "index_shops_on_tiktok_app_id"
    t.index ["tiktok_credential_id"], name: "index_shops_on_tiktok_credential_id"
    t.index ["tiktok_returns_last_polled_at"], name: "index_shops_on_tiktok_returns_last_polled_at"
    t.index ["tiktok_returns_last_seen_update_time"], name: "index_shops_on_tiktok_returns_last_seen_update_time"
  end

  create_table "sku_import_batches", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.boolean "dry_run", default: false, null: false
    t.string "stock_mode", default: "skip", null: false
    t.string "original_filename"
    t.integer "total_rows", default: 0, null: false
    t.integer "upsert_rows", default: 0, null: false
    t.integer "stock_updated", default: 0, null: false
    t.integer "stock_failed", default: 0, null: false
    t.jsonb "result", default: {}, null: false
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sku_import_batches_on_created_at"
    t.index ["status"], name: "index_sku_import_batches_on_status"
  end

  create_table "sku_mappings", force: :cascade do |t|
    t.string "channel", null: false
    t.bigint "shop_id", null: false
    t.string "external_sku", null: false
    t.bigint "sku_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_variant_id"
    t.index ["channel", "shop_id", "external_sku"], name: "uniq_sku_mappings", unique: true
    t.index ["channel", "shop_id", "external_variant_id"], name: "uniq_sku_mappings_variant", unique: true, where: "(external_variant_id IS NOT NULL)"
    t.index ["shop_id"], name: "index_sku_mappings_on_shop_id"
    t.index ["sku_id", "shop_id"], name: "index_sku_mappings_on_sku_id_and_shop_id"
    t.index ["sku_id"], name: "index_sku_mappings_on_sku_id"
  end

  create_table "skus", force: :cascade do |t|
    t.string "code", null: false
    t.string "barcode"
    t.string "brand"
    t.string "model"
    t.string "color"
    t.string "size"
    t.boolean "active", default: true, null: false
    t.datetime "archived_at"
    t.integer "buffer_quantity", default: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "stock_identity_id"
    t.index ["active"], name: "index_skus_on_active"
    t.index ["archived_at"], name: "index_skus_on_archived_at"
    t.index ["barcode"], name: "index_skus_on_barcode", unique: true
    t.index ["buffer_quantity"], name: "index_skus_on_buffer_quantity"
    t.index ["code"], name: "index_skus_on_code", unique: true
    t.index ["stock_identity_id"], name: "index_skus_on_stock_identity_id"
    t.check_constraint "buffer_quantity >= 0", name: "chk_sku_buffer_non_negative"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stock_count_lines", force: :cascade do |t|
    t.bigint "stock_count_session_id", null: false
    t.bigint "sku_id", null: false
    t.string "barcode_snapshot"
    t.string "sku_code_snapshot", null: false
    t.integer "system_qty_snapshot", default: 0, null: false
    t.integer "counted_qty", default: 0, null: false
    t.integer "diff_qty", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.string "idempotency_key", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_stock_count_lines_on_idempotency_key", unique: true
    t.index ["sku_id"], name: "index_stock_count_lines_on_sku_id"
    t.index ["status"], name: "index_stock_count_lines_on_status"
    t.index ["stock_count_session_id", "sku_id"], name: "idx_stock_count_lines_session_sku", unique: true
    t.index ["stock_count_session_id"], name: "index_stock_count_lines_on_stock_count_session_id"
    t.check_constraint "counted_qty >= 0", name: "chk_stock_count_lines_counted_qty_non_negative"
    t.check_constraint "system_qty_snapshot >= 0", name: "chk_stock_count_lines_system_qty_non_negative"
  end

  create_table "stock_count_sessions", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "session_number", null: false
    t.string "status", default: "open", null: false
    t.string "idempotency_key", null: false
    t.datetime "confirmed_at"
    t.datetime "cancelled_at"
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_stock_count_sessions_on_idempotency_key", unique: true
    t.index ["session_number"], name: "index_stock_count_sessions_on_session_number", unique: true
    t.index ["shop_id", "created_at"], name: "index_stock_count_sessions_on_shop_id_and_created_at"
    t.index ["shop_id"], name: "index_stock_count_sessions_on_shop_id"
    t.index ["status"], name: "index_stock_count_sessions_on_status"
  end

  create_table "stock_identities", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_stock_identities_on_code", unique: true
  end

  create_table "stock_movements", force: :cascade do |t|
    t.bigint "sku_id", null: false
    t.integer "delta_on_hand", null: false
    t.string "reason", null: false
    t.jsonb "meta", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reason"], name: "index_stock_movements_on_reason"
    t.index ["sku_id", "created_at"], name: "index_stock_movements_on_sku_id_and_created_at"
    t.index ["sku_id"], name: "index_stock_movements_on_sku_id"
  end

  create_table "stock_sync_requests", force: :cascade do |t|
    t.bigint "sku_id", null: false
    t.string "status", default: "pending", null: false
    t.string "last_reason"
    t.datetime "first_requested_at", null: false
    t.datetime "last_requested_at", null: false
    t.datetime "scheduled_for", null: false
    t.datetime "last_enqueued_at"
    t.datetime "last_processed_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_id"], name: "index_stock_sync_requests_on_sku_id", unique: true
    t.index ["status", "scheduled_for"], name: "index_stock_sync_requests_on_status_and_scheduled_for"
  end

  create_table "system_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "tiktok_apps", force: :cascade do |t|
    t.string "code", null: false
    t.string "auth_region", default: "ROW", null: false
    t.string "service_id", null: false
    t.string "app_key", null: false
    t.string "app_secret", null: false
    t.string "open_api_host", default: "https://open-api.tiktokglobalshop.com", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_tiktok_apps_on_active"
    t.index ["code"], name: "index_tiktok_apps_on_code", unique: true
  end

  create_table "tiktok_credentials", force: :cascade do |t|
    t.string "open_id", null: false
    t.integer "user_type", null: false
    t.string "seller_name"
    t.string "seller_base_region"
    t.text "access_token", null: false
    t.datetime "access_token_expires_at", null: false
    t.text "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.jsonb "granted_scopes", default: [], null: false
    t.boolean "active", default: true, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "tiktok_app_id"
    t.index ["tiktok_app_id", "open_id"], name: "index_tiktok_credentials_on_tiktok_app_id_and_open_id", unique: true
    t.index ["tiktok_app_id"], name: "index_tiktok_credentials_on_tiktok_app_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "file_batches", "shops"
  add_foreign_key "inventory_actions", "order_lines"
  add_foreign_key "inventory_actions", "skus"
  add_foreign_key "inventory_balances", "skus"
  add_foreign_key "inventory_balances", "stock_identities"
  add_foreign_key "inventory_reconcile_runs", "shops"
  add_foreign_key "lazada_credentials", "lazada_apps"
  add_foreign_key "marketplace_items", "shops"
  add_foreign_key "order_lines", "orders"
  add_foreign_key "order_lines", "skus"
  add_foreign_key "orders", "shops"
  add_foreign_key "oversell_allocations", "order_lines"
  add_foreign_key "oversell_allocations", "oversell_incidents"
  add_foreign_key "oversell_allocations", "skus"
  add_foreign_key "oversell_incidents", "skus"
  add_foreign_key "pos_exchanges", "pos_returns"
  add_foreign_key "pos_exchanges", "pos_sales"
  add_foreign_key "pos_exchanges", "pos_sales", column: "new_pos_sale_id"
  add_foreign_key "pos_exchanges", "shops"
  add_foreign_key "pos_return_lines", "pos_returns"
  add_foreign_key "pos_return_lines", "pos_sale_lines"
  add_foreign_key "pos_return_lines", "skus"
  add_foreign_key "pos_returns", "pos_sales"
  add_foreign_key "pos_returns", "shops"
  add_foreign_key "pos_sale_lines", "pos_sales"
  add_foreign_key "pos_sale_lines", "skus"
  add_foreign_key "pos_sales", "shops"
  add_foreign_key "return_scans", "order_lines"
  add_foreign_key "return_scans", "return_shipments"
  add_foreign_key "return_scans", "skus"
  add_foreign_key "return_shipment_lines", "order_lines"
  add_foreign_key "return_shipment_lines", "return_shipments"
  add_foreign_key "return_shipment_lines", "skus"
  add_foreign_key "return_shipments", "orders"
  add_foreign_key "return_shipments", "shops"
  add_foreign_key "shipping_export_batch_items", "orders"
  add_foreign_key "shipping_export_batch_items", "shipping_export_batches"
  add_foreign_key "shop_sku_sync_states", "shops"
  add_foreign_key "shop_sku_sync_states", "skus"
  add_foreign_key "shops", "lazada_apps"
  add_foreign_key "shops", "lazada_credentials"
  add_foreign_key "shops", "tiktok_apps"
  add_foreign_key "shops", "tiktok_credentials"
  add_foreign_key "sku_mappings", "shops"
  add_foreign_key "sku_mappings", "skus"
  add_foreign_key "skus", "stock_identities"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "stock_count_lines", "skus"
  add_foreign_key "stock_count_lines", "stock_count_sessions"
  add_foreign_key "stock_count_sessions", "shops"
  add_foreign_key "stock_movements", "skus"
  add_foreign_key "stock_sync_requests", "skus"
  add_foreign_key "tiktok_credentials", "tiktok_apps"
end

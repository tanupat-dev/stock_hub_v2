# frozen_string_literal: true

require "test_helper"

class Catalog::SyncSkuMasterFromCatalogTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @shop = Shop.create!(channel: "tiktok", shop_code: "tiktok_1", name: "TikTok 1", active: true)
  end

  test "does not auto-create SKU: missing sku codes are skipped and no mapping is created" do
    items = [{ "external_sku" => "SKU_NOT_EXIST", "external_variant_id" => "V1" }]

    assert_difference("Sku.count", 0) do
      assert_difference("SkuMapping.count", 0) do
        stats = Catalog::SyncSkuMasterFromCatalog.call!(shop: @shop, items: items, dry_run: false)
        assert_equal 1, stats[:scanned]
        assert_equal 1, stats[:candidate]
        assert_equal 1, stats[:skipped_missing_sku]
        assert_equal 0, stats[:upserted_sku_key]
        assert_equal 0, stats[:upserted_variant_key]
      end
    end
  end

  test "creates sku-key mapping when SKU exists and variant_id is blank" do
    sku = Sku.create!(code: "SKU1", barcode: "B1", buffer_quantity: 3)
    items = [{ "external_sku" => "SKU1", "external_variant_id" => nil }]

    assert_difference("SkuMapping.count", 1) do
      stats = Catalog::SyncSkuMasterFromCatalog.call!(shop: @shop, items: items, dry_run: false)
      assert_equal 1, stats[:upserted_sku_key]
      assert_equal 0, stats[:upserted_variant_key]
      assert_equal 1, stats[:mapping_changed]
      assert_equal [sku.id], stats[:affected_sku_ids]
    end

    m = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_sku: "SKU1")
    assert_equal sku.id, m.sku_id
    assert_nil m.external_variant_id
  end

  test "creates variant present => STILL ONLY 1 ROW (sku-key), and is findable by variant_id" do
    sku = Sku.create!(code: "SKU2", barcode: "B2", buffer_quantity: 3)
    items = [{ "external_sku" => "SKU2", "external_variant_id" => "V-2" }]

    assert_difference("SkuMapping.count", 1) do
      stats = Catalog::SyncSkuMasterFromCatalog.call!(shop: @shop, items: items, dry_run: false)
      assert_equal 1, stats[:upserted_sku_key]
      assert_equal 0, stats[:upserted_variant_key]
      assert_equal 1, stats[:mapping_changed]
      assert_equal [sku.id], stats[:affected_sku_ids]
    end

    m = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_sku: "SKU2")
    assert_equal sku.id, m.sku_id
    assert_equal "V-2", m.external_variant_id

    # หาได้ด้วย variant_id (แถวเดียวกัน)
    m2 = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_variant_id: "V-2")
    assert_equal m.id, m2.id
  end

  test "conflict guard: if variant_id already mapped to different sku, skip and do not change mapping" do
    sku_a = Sku.create!(code: "A", barcode: "BA", buffer_quantity: 3)
    _sku_b = Sku.create!(code: "B", barcode: "BB", buffer_quantity: 3)

    SkuMapping.create!(
      channel: "tiktok",
      shop_id: @shop.id,
      external_sku: "A",
      external_variant_id: "V-CONFLICT",
      sku_id: sku_a.id
    )

    items = [{ "external_sku" => "B", "external_variant_id" => "V-CONFLICT" }]

    assert_no_difference("SkuMapping.count") do
      stats = Catalog::SyncSkuMasterFromCatalog.call!(shop: @shop, items: items, dry_run: false)
      assert_equal 1, stats[:skipped_conflict_variant]
      assert_equal 0, stats[:upserted_sku_key]
      assert_equal 0, stats[:upserted_variant_key]
      assert_equal 0, stats[:mapping_changed]
    end

    m = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_variant_id: "V-CONFLICT")
    assert_equal sku_a.id, m.sku_id
  end

  test "dry_run: computes stats but does not write and does not enqueue" do
    sku = Sku.create!(code: "SKU3", barcode: "B3", buffer_quantity: 3)
    items = [{ "external_sku" => "SKU3", "external_variant_id" => "V-3" }]

    assert_no_difference("SkuMapping.count") do
      assert_no_enqueued_jobs do
        stats = Catalog::SyncSkuMasterFromCatalog.call!(
          shop: @shop,
          items: items,
          enqueue_sync_stock: true,
          dry_run: true
        )

        assert_equal 1, stats[:mapping_changed]
        assert_equal [sku.id], stats[:affected_sku_ids]
        assert_equal 0, stats[:upserted_sku_key]
        assert_equal 0, stats[:upserted_variant_key]
        assert_equal 0, stats[:enqueued_sync_stock]
      end
    end
  end

  test "enqueue_sync_stock: enqueues SyncStockJob only when mapping changes, not on second run" do
    sku = Sku.create!(code: "SKU4", barcode: "B4", buffer_quantity: 3)
    items = [{ "external_sku" => "SKU4", "external_variant_id" => "V-4" }]

    clear_enqueued_jobs

    Catalog::SyncSkuMasterFromCatalog.call!(
      shop: @shop,
      items: items,
      enqueue_sync_stock: true,
      dry_run: false
    )

    assert_equal 1, enqueued_jobs.size
    job = enqueued_jobs.first
    assert_equal "SyncStockJob", job["job_class"]
    assert_equal "sync_stock", job["queue_name"]

    args = job["arguments"]
    assert_equal sku.id, args[0]
    assert_equal "sku_mapping_synced", args[1]["reason"]
    assert_equal false, args[1]["force"]

    clear_enqueued_jobs

    Catalog::SyncSkuMasterFromCatalog.call!(
      shop: @shop,
      items: items,
      enqueue_sync_stock: true,
      dry_run: false
    )

    assert_equal 0, enqueued_jobs.size
  end

  test "items nil: loads from marketplace_items for this shop (variant present => 1 row)" do
    sku = Sku.create!(code: "SKU5", barcode: "B5", buffer_quantity: 3)

    MarketplaceItem.create!(
      shop_id: @shop.id,
      channel: "tiktok",
      external_variant_id: "V-5",
      external_sku: "SKU5",
      title: "x",
      status: "ACTIVE",
      available_stock: 10,
      raw_payload: {}
    )

    assert_difference("SkuMapping.count", 1) do
      stats = Catalog::SyncSkuMasterFromCatalog.call!(shop: @shop, items: nil, dry_run: false)
      assert_equal 1, stats[:scanned]
      assert_equal 1, stats[:candidate]
      assert_equal 1, stats[:upserted_sku_key]
      assert_equal 0, stats[:upserted_variant_key]
      assert_equal [sku.id], stats[:affected_sku_ids]
    end

    m = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_sku: "SKU5")
    assert_equal sku.id, m.sku_id
    assert_equal "V-5", m.external_variant_id

    m2 = SkuMapping.find_by!(channel: "tiktok", shop_id: @shop.id, external_variant_id: "V-5")
    assert_equal m.id, m2.id
  end
end
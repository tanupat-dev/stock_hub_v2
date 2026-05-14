# test/services/stock_sync/push_sku_test.rb
require "test_helper"

class StockSync::PushSkuTest < ActiveSupport::TestCase
  def setup
    @tiktok_app = TiktokApp.create!(
      code: "push-sku-app",
      service_id: "svc-push",
      app_key: "key-push",
      app_secret: "sec-push"
    )
    @tiktok_cred = TiktokCredential.create!(
      tiktok_app: @tiktok_app,
      open_id: "OID-PUSH-1",
      user_type: 1,
      access_token: "tok-push",
      access_token_expires_at: 1.year.from_now,
      refresh_token: "rtok-push",
      refresh_token_expires_at: 1.year.from_now
    )
    @shop = Shop.create!(
      channel: "tiktok",
      shop_code: "tt-push-1",
      name: "TT Push",
      active: true,
      stock_sync_enabled: true,
      tiktok_credential_id: @tiktok_cred.id,
      shop_cipher: "CIPHER-PUSH"
    )
    @identity = StockIdentity.create!
    @sku = Sku.create!(code: "PUSH-SKU-A", barcode: "P-BA", buffer_quantity: 0, stock_identity: @identity)
    @balance = InventoryBalance.create!(stock_identity: @identity, sku: @sku, on_hand: 10, reserved: 0)
    @mapping = SkuMapping.create!(
      channel: "tiktok",
      shop: @shop,
      sku: @sku,
      external_sku: "EXT-PUSH-A",
      external_variant_id: "VAR-PUSH-001"
    )
    @item = MarketplaceItem.create!(
      shop: @shop,
      channel: "tiktok",
      external_product_id: "PROD-PUSH-001",
      external_variant_id: "VAR-PUSH-001",
      external_sku: "EXT-PUSH-A",
      status: "ACTIVATE"
    )
  end

  def enable_rollout!
    StockSync::Rollout.set_global_enabled!(true)
  end

  # -------------------------------------------------------
  # Return value
  # -------------------------------------------------------
  test "returns online_available for the sku" do
    # on_hand=10, reserved=0, buffer=0 → available=10
    result = StockSync::PushSku.call!(sku: @sku, reason: "test")
    assert_equal 10, result
  end

  # -------------------------------------------------------
  # Happy path: TikTok enqueue
  # -------------------------------------------------------
  test "enqueues PushInventoryJob for active TikTok shop when all conditions met" do
    enable_rollout!
    assert_enqueued_jobs(1, only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  # -------------------------------------------------------
  # Rollout controls
  # -------------------------------------------------------
  test "skips all shops when global sync is disabled (default test state)" do
    # No SystemSetting record → global_enabled? defaults to false
    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "skips when shop is not active" do
    enable_rollout!
    @shop.update!(active: false)

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "skips when shop stock_sync_enabled is false" do
    enable_rollout!
    @shop.update!(stock_sync_enabled: false)

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  # -------------------------------------------------------
  # Cooldown / no-change logic
  # -------------------------------------------------------
  test "skips when last_pushed_available equals current available (no_change)" do
    enable_rollout!
    ShopSkuSyncState.create!(shop: @shop, sku: @sku, last_pushed_available: 10, last_pushed_at: 2.hours.ago, fail_count: 0)

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "skips when same value was pushed within the 30-minute cooldown window" do
    enable_rollout!
    ShopSkuSyncState.create!(shop: @shop, sku: @sku, last_pushed_available: 10, last_pushed_at: 10.minutes.ago, fail_count: 0)

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "enqueues when available value changed since last push" do
    enable_rollout!
    ShopSkuSyncState.create!(shop: @shop, sku: @sku, last_pushed_available: 5, last_pushed_at: 10.minutes.ago, fail_count: 0)

    assert_enqueued_jobs(1, only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "force: true bypasses no_change and enqueues anyway" do
    enable_rollout!
    ShopSkuSyncState.create!(shop: @shop, sku: @sku, last_pushed_available: 10, last_pushed_at: 2.hours.ago, fail_count: 0)

    assert_enqueued_jobs(1, only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test", force: true)
    end
  end

  # -------------------------------------------------------
  # MarketplaceItem checks
  # -------------------------------------------------------
  test "skips when marketplace item status is not ACTIVATE" do
    enable_rollout!
    @item.update!(status: "INACTIVE")

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  test "skips as pending_duplicate when an unfinished PushInventoryJob already exists in SolidQueue" do
    enable_rollout!
    SolidQueue::Job.create!(
      queue_name: "sync_stock",
      class_name: "PushInventoryJob",
      arguments: "[#{@shop.id}, #{@item.id}, 10, {\"reason\": \"stock_sync.push_sku\"}]",
      priority: 0,
      finished_at: nil
    )

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  # -------------------------------------------------------
  # Channel-specific skips (isolated SKUs)
  # -------------------------------------------------------
  test "skips POS channel shops" do
    enable_rollout!
    pos_shop = Shop.create!(channel: "pos", shop_code: "pos-push-1", name: "POS Push", active: true, stock_sync_enabled: true)
    iso_sku = Sku.create!(code: "PUSH-POS-SKU", barcode: "P-POS-B", buffer_quantity: 0)
    InventoryBalance.create!(sku: iso_sku, on_hand: 5, reserved: 0)
    SkuMapping.create!(channel: "pos", shop: pos_shop, sku: iso_sku, external_sku: "POS-EXT")

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: iso_sku, reason: "test")
    end
  end

  test "skips Shopee channel (adapter not yet implemented)" do
    enable_rollout!
    shopee_shop = Shop.create!(channel: "shopee", shop_code: "sp-push-1", name: "SP Push", active: true, stock_sync_enabled: true)
    iso_sku = Sku.create!(code: "PUSH-SP-SKU", barcode: "P-SP-B", buffer_quantity: 0)
    InventoryBalance.create!(sku: iso_sku, on_hand: 5, reserved: 0)
    SkuMapping.create!(channel: "shopee", shop: shopee_shop, sku: iso_sku, external_sku: "SP-EXT", external_variant_id: "SP-VAR")

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: iso_sku, reason: "test")
    end
  end

  test "skips TikTok shop with missing tiktok_credential_id" do
    enable_rollout!
    shop_nc = Shop.create!(channel: "tiktok", shop_code: "tt-nc-push", name: "TT NC", active: true, stock_sync_enabled: true, shop_cipher: "CIPHER-NC")
    iso_sku = Sku.create!(code: "PUSH-NC-SKU", barcode: "P-NC-B", buffer_quantity: 0)
    InventoryBalance.create!(sku: iso_sku, on_hand: 5, reserved: 0)
    SkuMapping.create!(channel: "tiktok", shop: shop_nc, sku: iso_sku, external_sku: "NC-EXT", external_variant_id: "NC-VAR")
    MarketplaceItem.create!(shop: shop_nc, channel: "tiktok", external_product_id: "NC-P", external_variant_id: "NC-VAR", external_sku: "NC-EXT", status: "ACTIVATE")

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: iso_sku, reason: "test")
    end
  end

  test "skips TikTok shop with blank shop_cipher" do
    enable_rollout!
    cred2 = TiktokCredential.create!(
      tiktok_app: @tiktok_app,
      open_id: "OID-NCI-2",
      user_type: 1,
      access_token: "tok-nci",
      access_token_expires_at: 1.year.from_now,
      refresh_token: "rtok-nci",
      refresh_token_expires_at: 1.year.from_now
    )
    shop_nci = Shop.create!(channel: "tiktok", shop_code: "tt-nci-push", name: "TT NCI", active: true, stock_sync_enabled: true, tiktok_credential_id: cred2.id)
    iso_sku = Sku.create!(code: "PUSH-NCI-SKU", barcode: "P-NCI-B", buffer_quantity: 0)
    InventoryBalance.create!(sku: iso_sku, on_hand: 5, reserved: 0)
    SkuMapping.create!(channel: "tiktok", shop: shop_nci, sku: iso_sku, external_sku: "NCI-EXT", external_variant_id: "NCI-VAR")
    MarketplaceItem.create!(shop: shop_nci, channel: "tiktok", external_product_id: "NCI-P", external_variant_id: "NCI-VAR", external_sku: "NCI-EXT", status: "ACTIVATE")

    assert_no_enqueued_jobs(only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: iso_sku, reason: "test")
    end
  end

  # -------------------------------------------------------
  # Stock identity grouping
  # -------------------------------------------------------
  test "processes all SKUs sharing the same stock identity" do
    enable_rollout!
    cred3 = TiktokCredential.create!(
      tiktok_app: @tiktok_app,
      open_id: "OID-GROUP-3",
      user_type: 1,
      access_token: "tok-grp",
      access_token_expires_at: 1.year.from_now,
      refresh_token: "rtok-grp",
      refresh_token_expires_at: 1.year.from_now
    )
    shop2 = Shop.create!(
      channel: "tiktok", shop_code: "tt-push-grp2", name: "TT G2",
      active: true, stock_sync_enabled: true,
      tiktok_credential_id: cred3.id, shop_cipher: "CIPHER-G2"
    )
    sku2 = Sku.create!(code: "PUSH-SKU-B", barcode: "P-BB", buffer_quantity: 0, stock_identity: @identity)
    SkuMapping.create!(channel: "tiktok", shop: shop2, sku: sku2, external_sku: "EXT-PUSH-B", external_variant_id: "VAR-PUSH-B")
    MarketplaceItem.create!(
      shop: shop2, channel: "tiktok",
      external_product_id: "PROD-PUSH-B", external_variant_id: "VAR-PUSH-B",
      external_sku: "EXT-PUSH-B", status: "ACTIVATE"
    )

    # @sku → @shop and sku2 → shop2 both get a job (two SKUs, same identity)
    assert_enqueued_jobs(2, only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: @sku, reason: "test")
    end
  end

  # -------------------------------------------------------
  # Lazada happy path
  # -------------------------------------------------------
  test "enqueues PushInventoryJob for active Lazada shop" do
    enable_rollout!
    lz_app = LazadaApp.create!(code: "lz-push-app", app_key: "lzkey", app_secret: "lzsec")
    lz_cred = LazadaCredential.create!(lazada_app: lz_app, access_token: "lztok", refresh_token: "lzrtok")
    lz_shop = Shop.create!(
      channel: "lazada", shop_code: "lz-push-1", name: "LZ Push",
      active: true, stock_sync_enabled: true,
      lazada_credential_id: lz_cred.id, lazada_app_id: lz_app.id
    )
    iso_sku = Sku.create!(code: "PUSH-LZ-SKU", barcode: "P-LZ-B", buffer_quantity: 0)
    InventoryBalance.create!(sku: iso_sku, on_hand: 8, reserved: 0)
    SkuMapping.create!(channel: "lazada", shop: lz_shop, sku: iso_sku, external_sku: "LZ-EXT", external_variant_id: "LZ-VAR")
    MarketplaceItem.create!(
      shop: lz_shop, channel: "lazada",
      external_product_id: "LZ-PROD", external_variant_id: "LZ-VAR",
      external_sku: "LZ-EXT", status: "ACTIVATE"
    )

    assert_enqueued_jobs(1, only: PushInventoryJob) do
      StockSync::PushSku.call!(sku: iso_sku, reason: "test")
    end
  end
end

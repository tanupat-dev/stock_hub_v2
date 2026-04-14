# frozen_string_literal: true

module Catalog
  class SyncSkuMasterFromCatalog
    class Error < StandardError; end

    def self.call!(
      shop:,
      items: nil,
      match_by: :code,
      enqueue_sync_stock: false,
      dry_run: false
    )
      new(shop:, items:, match_by:, enqueue_sync_stock:, dry_run:).call!
    end

    def initialize(shop:, items:, match_by:, enqueue_sync_stock:, dry_run:)
      @shop = shop
      @items = items
      @match_by = match_by&.to_sym
      @enqueue_sync_stock = enqueue_sync_stock
      @dry_run = dry_run

      raise ArgumentError, "shop is required" if @shop.nil?
      raise ArgumentError, "shop.channel is required" if @shop.channel.blank?
      raise ArgumentError, "unsupported match_by=#{@match_by}" unless @match_by == :code
    end

    def call!
      rows = normalize_items(@items)

      stats = {
        ok: true,
        shop_id: @shop.id,
        shop_code: @shop.shop_code,
        channel: @shop.channel,
        dry_run: @dry_run,
        scanned: rows.size,
        active_rows: 0,
        skipped_non_activate: 0,
        candidate: 0,
        skipped_blank_external_sku: 0,
        skipped_duplicate_activate_sku: 0,
        skipped_missing_sku: 0,
        skipped_conflict_variant: 0,
        duplicates_activate_sku_count: 0,
        duplicates_activate_sku_all: [],
        upserted_sku_key: 0,
        upserted_variant_key: 0,
        mapping_changed: 0,
        affected_sku_ids: [],
        enqueued_sync_stock: 0
      }

      active_rows = rows.select { |r| r[:status].to_s.upcase == "ACTIVATE" }
      stats[:active_rows] = active_rows.size
      stats[:skipped_non_activate] = rows.size - active_rows.size
      return stats.merge(note: "no_activate_rows") if active_rows.empty?

      active_rows.each do |r|
        if r[:external_sku].blank? && r[:external_variant_id].present?
          log_warn(
            event: "catalog.sync_sku_master.blank_external_sku_but_has_variant",
            shop_id: @shop.id,
            shop_code: @shop.shop_code,
            channel: @shop.channel,
            status: r[:status],
            external_variant_id: r[:external_variant_id]
          )
        end
      end

      candidates = active_rows.select { |r| r[:external_sku].present? }
      stats[:candidate] = candidates.size
      stats[:skipped_blank_external_sku] = active_rows.size - candidates.size
      return stats.merge(note: "no_candidates_after_blank_filter") if candidates.empty?

      dup_map =
        candidates
          .group_by { |r| r[:external_sku].to_s }
          .select { |_ext_sku, arr| arr.size > 1 }

      duplicate_skus = dup_map.keys.sort
      stats[:duplicates_activate_sku_count] = duplicate_skus.size
      stats[:duplicates_activate_sku_all] = duplicate_skus

      external_skus_all = candidates.map { |r| r[:external_sku] }.uniq
      skus_by_code = Sku.where(code: external_skus_all).index_by(&:code)

      if duplicate_skus.any?
        stats[:skipped_duplicate_activate_sku] = duplicate_skus.size

        duplicate_skus.each do |ext_sku|
          sku = skus_by_code[ext_sku] || Sku.find_by(code: ext_sku)
          next if sku.nil?

          freeze_sku_if_duplicate_activate!(
            sku: sku,
            external_sku: ext_sku,
            rows: dup_map[ext_sku]
          )
        end

        candidates = candidates.reject { |r| duplicate_skus.include?(r[:external_sku].to_s) }
        return stats.merge(note: "no_candidates_after_duplicate_freeze") if candidates.empty?
      end

      by_sku = {}

      candidates.each do |r|
        ext_sku = r[:external_sku].to_s
        cur = by_sku[ext_sku]

        if cur.nil?
          by_sku[ext_sku] = r
          next
        end

        cur_vid = cur[:external_variant_id].to_s.presence
        new_vid = r[:external_variant_id].to_s.presence

        pick =
          if cur_vid.nil? && new_vid.present?
            r
          elsif cur_vid.present? && new_vid.nil?
            cur
          elsif cur_vid.present? && new_vid.present?
            (new_vid < cur_vid) ? r : cur
          else
            cur
          end

        if cur_vid.present? && new_vid.present? && cur_vid != new_vid
          log_warn(
            event: "catalog.sync_sku_master.duplicate_external_sku_after_filter",
            shop_id: @shop.id,
            shop_code: @shop.shop_code,
            channel: @shop.channel,
            external_sku: ext_sku,
            kept_external_variant_id: pick[:external_variant_id],
            dropped_external_variant_id: (pick == r ? cur[:external_variant_id] : r[:external_variant_id])
          )
        end

        by_sku[ext_sku] = pick
      end

      candidates = by_sku.values

      external_skus = candidates.map { |r| r[:external_sku] }.uniq
      skus_by_code = skus_by_code.slice(*external_skus)

      ext_variant_ids = candidates.map { |r| r[:external_variant_id] }.compact.uniq

      existing_by_ext_sku =
        SkuMapping.where(channel: @shop.channel, shop_id: @shop.id, external_sku: external_skus)
                  .index_by(&:external_sku)

      existing_by_variant =
        if ext_variant_ids.any?
          SkuMapping.where(channel: @shop.channel, shop_id: @shop.id, external_variant_id: ext_variant_ids)
                    .where.not(external_variant_id: nil)
                    .index_by(&:external_variant_id)
        else
          {}
        end

      now = Time.current
      upsert_rows_sku_key = []

      candidates.each do |r|
        ext_sku = r[:external_sku]
        ext_vid = r[:external_variant_id]

        sku = skus_by_code[ext_sku]
        if sku.nil?
          stats[:skipped_missing_sku] += 1
          next
        end

        if ext_vid.present?
          existing_v = existing_by_variant[ext_vid]
          if existing_v && existing_v.sku_id.present? && existing_v.sku_id != sku.id
            stats[:skipped_conflict_variant] += 1
            log_warn(
              event: "catalog.sync_sku_master.conflict_variant",
              shop_id: @shop.id,
              shop_code: @shop.shop_code,
              channel: @shop.channel,
              external_variant_id: ext_vid,
              external_sku: ext_sku,
              sku_id_wanted: sku.id,
              sku_id_existing: existing_v.sku_id,
              mapping_id: existing_v.id
            )
            next
          end
        end

        changed = mapping_would_change?(
          existing_by_ext_sku: existing_by_ext_sku,
          existing_by_variant: existing_by_variant,
          external_sku: ext_sku,
          external_variant_id: ext_vid,
          sku_id: sku.id
        )

        if changed
          stats[:mapping_changed] += 1
          stats[:affected_sku_ids] << sku.id
        end

        next if @dry_run

        upsert_rows_sku_key << {
          channel: @shop.channel,
          shop_id: @shop.id,
          external_sku: ext_sku,
          external_variant_id: ext_vid,
          sku_id: sku.id,
          created_at: now,
          updated_at: now
        }
      end

      if !@dry_run && upsert_rows_sku_key.any?
        SkuMapping.upsert_all(
          upsert_rows_sku_key,
          unique_by: :uniq_sku_mappings,
          record_timestamps: false,
          update_only: %i[sku_id external_variant_id updated_at]
        )
        stats[:upserted_sku_key] = upsert_rows_sku_key.size
      end

      stats[:upserted_variant_key] = 0
      stats[:affected_sku_ids] = stats[:affected_sku_ids].uniq

      log_info(
        event: "catalog.sync_sku_master.done",
        shop_id: @shop.id,
        shop_code: @shop.shop_code,
        channel: @shop.channel,
        dry_run: @dry_run,
        scanned: stats[:scanned],
        active_rows: stats[:active_rows],
        skipped_non_activate: stats[:skipped_non_activate],
        candidate: stats[:candidate],
        skipped_blank_external_sku: stats[:skipped_blank_external_sku],
        duplicates_activate_sku_count: stats[:duplicates_activate_sku_count],
        duplicates_activate_sku_all: stats[:duplicates_activate_sku_all],
        skipped_duplicate_activate_sku: stats[:skipped_duplicate_activate_sku],
        skipped_missing_sku: stats[:skipped_missing_sku],
        skipped_conflict_variant: stats[:skipped_conflict_variant],
        mapping_changed: stats[:mapping_changed],
        upserted_sku_key: stats[:upserted_sku_key],
        upserted_variant_key: stats[:upserted_variant_key]
      )

      if @enqueue_sync_stock && !@dry_run && stats[:affected_sku_ids].any?
        stats[:affected_sku_ids].each do |sku_id|
          sku = Sku.find_by(id: sku_id)
          next if sku.nil?

          StockSync::RequestDebouncer.call!(
            sku: sku,
            reason: "sku_mapping_synced"
          )
          stats[:enqueued_sync_stock] += 1
        end
      end

      # ✅ NEW: remap downstream references
      begin
        affected_external_skus = rows.map { |r| r[:external_sku].to_s.strip }.uniq

        Inventory::RemapSkuReferences.call!(
          shop: @shop,
          channel: @shop.channel,
          external_skus: affected_external_skus
        )
      rescue => e
        log_error(
          event: "catalog.sync_sku_master.remap_failed",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          channel: @shop.channel,
          err_class: e.class.name,
          err_message: e.message
        )
      end

      stats
    rescue => e
      log_error(
        event: "catalog.sync_sku_master.fail",
        shop_id: @shop&.id,
        shop_code: @shop&.shop_code,
        channel: @shop&.channel,
        err_class: e.class.name,
        err_message: e.message
      )
      raise
    end

    private

    def normalize_items(items)
      if items.nil?
        MarketplaceItem.where(shop_id: @shop.id)
                       .pluck(:external_sku, :external_variant_id, :status)
                       .map do |external_sku, external_variant_id, status|
          {
            external_sku: external_sku.to_s.strip.presence,
            external_variant_id: external_variant_id.to_s.strip.presence,
            status: status.to_s.strip.presence
          }
        end
      else
        Array(items).map do |h|
          ext_sku = (h[:external_sku] || h["external_sku"]).to_s.strip.presence
          ext_vid = (h[:external_variant_id] || h["external_variant_id"]).to_s.strip.presence
          st =
            (h[:status] || h["status"] ||
             h[:product_status] || h["product_status"]).to_s.strip.presence

          { external_sku: ext_sku, external_variant_id: ext_vid, status: st }
        end
      end
    end

    def freeze_sku_if_duplicate_activate!(sku:, external_sku:, rows:)
      return if @dry_run

      variant_ids = Array(rows).map { |r| r[:external_variant_id].to_s.presence }.compact.uniq
      payload = {
        channel: @shop.channel,
        shop_id: @shop.id,
        shop_code: @shop.shop_code,
        external_sku: external_sku,
        duplicate_count: rows.size,
        variant_ids: variant_ids.first(50)
      }

      begin
        Inventory::SystemFreeze.call!(
          sku: sku,
          reason: "catalog_duplicate_activate_sku",
          meta: payload
        )

        log_warn(
          event: "catalog.sync_sku_master.duplicate_activate_sku_frozen",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          channel: @shop.channel,
          sku_id: sku.id,
          external_sku: external_sku,
          dup_count: rows.size,
          sample_variant_ids: variant_ids.first(10)
        )
      rescue => e
        log_error(
          event: "catalog.sync_sku_master.duplicate_activate_sku_freeze_failed",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          channel: @shop.channel,
          sku_id: sku.id,
          external_sku: external_sku,
          err_class: e.class.name,
          err_message: e.message
        )
      end
    end

    def mapping_would_change?(existing_by_ext_sku:, existing_by_variant:, external_sku:, external_variant_id:, sku_id:)
      ex_s = existing_by_ext_sku[external_sku]
      sku_key_changed =
        ex_s.nil? ||
        ex_s.sku_id.to_i != sku_id.to_i ||
        (external_variant_id.present? && ex_s.external_variant_id.to_s != external_variant_id.to_s)

      variant_changed = false
      if external_variant_id.present?
        ex_v = existing_by_variant[external_variant_id]
        variant_changed =
          ex_v.nil? ||
          ex_v.sku_id.to_i != sku_id.to_i ||
          ex_v.external_sku.to_s != external_sku.to_s
      end

      sku_key_changed || variant_changed
    end

    def log_info(payload)
      Rails.logger.info(payload.to_json)
    end

    def log_warn(payload)
      Rails.logger.warn(payload.to_json)
    end

    def log_error(payload)
      Rails.logger.error(payload.to_json)
    end
  end
end

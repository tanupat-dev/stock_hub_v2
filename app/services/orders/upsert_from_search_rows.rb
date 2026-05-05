# frozen_string_literal: true

module Orders
  class UpsertFromSearchRows
    RESERVE_STATUSES = %w[
      ON_HOLD
      AWAITING_FULFILLMENT
      READY_TO_SHIP
      PARTIALLY_SHIPPING
    ].freeze

    COMMIT_STATUSES = %w[
      IN_TRANSIT
    ].freeze

    RELEASE_STATUSES = %w[
      CANCELLED
    ].freeze

    NOOP_STATUSES = %w[
      UNPAID
      DELIVERED
      COMPLETED
    ].freeze

    def self.call!(shop:, rows:)
      new(shop:, rows:).call!
    end

    def initialize(shop:, rows:)
      @shop = shop
      @rows = rows || []
      @now = Time.current
    end

    def call!
      return 0 if @rows.blank?

      external_ids = @rows.map { |r| r["id"].to_s }.reject(&:blank?).uniq
      existing =
        Order.where(channel: "tiktok", shop_id: @shop.id, external_order_id: external_ids)
             .index_by(&:external_order_id)

      @rows.each do |r|
        external_order_id = r["id"].to_s
        next if external_order_id.blank?

        incoming_status = normalize_tiktok_status(r)
        incoming_update_time = r["update_time"].to_i

        order = existing[external_order_id]
        prev_status = order&.status
        prev_update_time = order&.updated_time_external.to_i

        skip_reason = Orders::StatusUpdateGuard.skip_reason(
          previous_status: prev_status,
          incoming_status: incoming_status,
          previous_update_time: prev_update_time,
          incoming_update_time: incoming_update_time,
          compare_update_time: true
        )

        if skip_reason.present?
          Orders::StatusUpdateGuard.log_skip!(
            channel: "tiktok",
            shop_id: @shop.id,
            external_order_id: external_order_id,
            previous_status: prev_status,
            incoming_status: incoming_status,
            previous_update_time: prev_update_time,
            incoming_update_time: incoming_update_time,
            reason: skip_reason
          )

          next
        end

        payload = r.merge("status" => incoming_status)

        order = upsert_order!(external_order_id, incoming_status, incoming_update_time, payload)
        existing[external_order_id] ||= order

        mapping_changed = upsert_lines!(order, payload)

        should_apply =
          prev_status != incoming_status ||
          incoming_update_time > prev_update_time ||
          mapping_changed

        if should_apply
          apply_inventory!(order, payload, prev_status)
        else
          repair_missing_inventory_actions!(order, payload, prev_status)
        end
      end

      @rows.size
    end

    private

    def normalize_tiktok_status(row)
      raw_status = row["status"].to_s

      has_tracking = Orders::StatusTracking.any_in_order_payload?(row)

      case raw_status
      when "AWAITING_SHIPMENT"
        has_tracking ? "READY_TO_SHIP" : "AWAITING_FULFILLMENT"
      when "AWAITING_COLLECTION"
        "READY_TO_SHIP"
      else
        raw_status
      end
    end

    def upsert_order!(external_id, status, update_time, payload)
      existing =
        Order.find_by(
          channel: "tiktok",
          shop_id: @shop.id,
          external_order_id: external_id
        )

      buyer_name = extract_buyer_name(payload).presence || existing&.buyer_name
      province   = extract_province(payload).presence || existing&.province
      buyer_note = extract_buyer_note(payload).presence || existing&.buyer_note

      attrs = {
        channel: "tiktok",
        shop_id: @shop.id,
        external_order_id: external_id,
        status: status,
        buyer_name: buyer_name,
        province: province,
        buyer_note: buyer_note,
        updated_time_external: update_time,
        updated_at_external: (update_time > 0 ? Time.at(update_time) : nil),
        raw_payload: payload,
        created_at: @now,
        updated_at: @now
      }

      Order.upsert_all(
        [ attrs ],
        unique_by: :uniq_orders_channel_shop_external,
        record_timestamps: false,
        update_only: %i[
          status
          buyer_name
          province
          buyer_note
          updated_time_external
          updated_at_external
          raw_payload
          updated_at
        ]
      )

      Order.find_by!(
        channel: "tiktok",
        shop_id: @shop.id,
        external_order_id: external_id
      )
    end

    def upsert_lines!(order, row)
      items = Array(row["line_items"])
      return false if items.blank?

      external_skus =
        items
          .map { |li| li["seller_sku"].to_s.presence || li["sku_id"].to_s }
          .map { |v| v.to_s.strip }
          .reject(&:blank?)
          .uniq

      mappings =
        SkuMapping
          .includes(:sku)
          .where(channel: "tiktok", shop_id: @shop.id, external_sku: external_skus)
          .index_by(&:external_sku)

      mapping_changed = false

      items.each do |li|
        external_line_id = li["id"].to_s.presence
        external_sku = (li["seller_sku"].to_s.presence || li["sku_id"].to_s).to_s.strip
        next if external_sku.blank?

        mapping = mappings[external_sku]

        sku =
          mapping&.sku ||
          find_sku_exact(external_sku)

        if mapping.blank? && sku.present?
          mapping = find_or_create_mapping!(external_sku, sku)
          mappings[external_sku] = mapping if mapping.present?
        end

        sku_id = sku&.id
        qty = [ li["quantity"].to_i, 1 ].max

        existing_line = existing_line_for(
          order: order,
          external_line_id: external_line_id,
          external_sku: external_sku
        )

        if sku_id.present?
          if existing_line.nil?
            mapping_changed = true
          elsif existing_line.sku_id != sku_id
            mapping_changed = true
          elsif missing_all_inventory_actions?(existing_line)
            mapping_changed = true
          end
        end

        idk =
          existing_line&.idempotency_key.presence ||
          build_canonical_idempotency_key(order, external_line_id, external_sku)

        OrderLine.upsert_all(
          [ {
            order_id: order.id,
            external_line_id: external_line_id,
            external_sku: external_sku,
            sku_id: sku_id,
            quantity: qty,
            status: li["display_status"].to_s,
            idempotency_key: idk,
            raw_payload: li,
            created_at: @now,
            updated_at: @now
          } ],
          unique_by: :index_order_lines_on_idempotency_key,
          record_timestamps: false,
          update_only: %i[
            external_line_id
            external_sku
            sku_id
            quantity
            status
            raw_payload
            updated_at
          ]
        )
      end

      mapping_changed
    end

    def existing_line_for(order:, external_line_id:, external_sku:)
      if external_line_id.present?
        line =
          OrderLine.find_by(
            order_id: order.id,
            external_line_id: external_line_id
          )

        return line if line.present?
      end

      return nil if external_sku.blank?

      OrderLine
        .where(order_id: order.id, external_sku: external_sku)
        .order(:id)
        .first
    end

    def build_canonical_idempotency_key(order, external_line_id, external_sku)
      base = external_line_id.presence || external_sku.presence || SecureRandom.uuid

      "tiktok:order:#{order.external_order_id}:line:#{base}"
    end

    def find_sku_exact(code)
      return nil if code.blank?

      Sku.find_by(code: code)
    end

    def find_or_create_mapping!(external_sku, sku)
      SkuMapping.find_or_create_by!(
        channel: "tiktok",
        shop_id: @shop.id,
        external_sku: external_sku
      ) do |mapping|
        mapping.sku_id = sku.id
      end
    rescue ActiveRecord::RecordNotUnique
      SkuMapping.find_by(
        channel: "tiktok",
        shop_id: @shop.id,
        external_sku: external_sku
      )
    end

    def missing_all_inventory_actions?(line)
      InventoryAction
        .where(order_line_id: line.id, action_type: %w[reserve commit release])
        .none?
    end

    def apply_inventory!(order, payload, previous_status)
      Orders::Tiktok::ApplyPolicy.call!(
        order: order,
        raw_order: payload,
        previous_status: previous_status
      )
    end

    def repair_missing_inventory_actions!(order, payload, previous_status)
      Orders::RepairMissingInventoryActions.call!(
        order: order,
        raw_order: payload,
        previous_status: previous_status,
        source: "tiktok_search_row_no_policy_apply"
      )
    end

    def extract_buyer_name(payload)
      payload.dig("recipient_address", "name").to_s.strip.presence
    end

    def extract_province(payload)
      district_info = Array(payload.dig("recipient_address", "district_info"))

      district_info.find { |row| row["address_level"].to_s == "L1" }
                   &.dig("address_name")
                   .to_s
                   .strip
                   .presence
    end

    def extract_buyer_note(payload)
      payload["buyer_message"].to_s.strip.presence
    end
  end
end

# frozen_string_literal: true

module Pos
  class SkusController < BaseController
    # GET /pos/skus/facets
    def facets
      base = Sku.all
      base = base.where(active: true) unless active_only_false?

      brands_scope = apply_q_filter(base)

      models_scope = brands_scope
      models_scope = models_scope.where(brand: params[:brand].to_s.strip) if params[:brand].present?

      colors_scope = models_scope
      colors_scope = colors_scope.where(model: params[:model].to_s.strip) if params[:model].present?

      sizes_scope = colors_scope
      sizes_scope = sizes_scope.where(color: params[:color].to_s.strip) if params[:color].present?

      render json: {
        ok: true,
        filters: current_filters,
        facets: {
          brands: distinct_values(brands_scope, :brand),
          models: distinct_values(models_scope, :model),
          colors: distinct_values(colors_scope, :color),
          sizes: distinct_values(sizes_scope, :size)
        }
      }
    rescue => e
      Rails.logger.error(
        {
          event: "pos.skus.facets.failed",
          err_class: e.class.name,
          err_message: e.message,
          filters: current_filters
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # GET /pos/skus/search
    def search
      scope = filtered_scope
      limit = normalized_limit

      skus = scope
        .includes(:inventory_balance, sku_mappings: :shop)
        .order(:brand, :model, :color, :size, :code)
        .limit(limit)
        .to_a

      render json: {
        ok: true,
        filters: current_filters.merge(limit: limit),
        count: skus.size,
        skus: skus.map { |sku| serialize_sku(sku) }
      }
    rescue => e
      Rails.logger.error(
        {
          event: "pos.skus.search.failed",
          err_class: e.class.name,
          err_message: e.message,
          filters: current_filters.merge(limit: params[:limit].presence)
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    # GET /pos/skus/:id/ledger
    def ledger
      sku = Sku.includes(:inventory_balance, sku_mappings: :shop).find(params[:id])
      limit = normalized_ledger_limit

      include_actions = truthy_param_default_true?(:include_actions)
      include_movements = truthy_param_default_true?(:include_movements)

      entries = []

      if include_actions
        InventoryAction
          .includes(order_line: { order: :shop })
          .where(sku_id: sku.id)
          .order(created_at: :desc, id: :desc)
          .limit(limit)
          .to_a
          .each do |action|
            entries << serialize_inventory_action(action)
          end
      end

      if include_movements
        StockMovement
          .where(sku_id: sku.id)
          .order(created_at: :desc, id: :desc)
          .limit(limit)
          .to_a
          .each do |movement|
            entries << serialize_stock_movement(movement)
          end
      end

      entries = entries
        .sort_by { |e| [ e[:occurred_at] || "", e[:id] || 0 ] }
        .reverse
        .first(limit)

      render json: {
        ok: true,
        sku: serialize_ledger_sku(sku),
        ledger: {
          count: entries.size,
          entries: entries
        }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue => e
      Rails.logger.error(
        {
          event: "pos.skus.ledger.failed",
          err_class: e.class.name,
          err_message: e.message,
          sku_id: params[:id],
          limit: params[:limit]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def freeze
      sku = Sku.find(params[:id])
      idempotency_key = params[:idempotency_key].presence || "ui:freeze:sku=#{sku.id}:#{Time.current.to_i}"

      before = sku_snapshot(sku)

      result = Inventory::Freeze.call!(
        sku: sku,
        reason: "manual",
        idempotency_key: idempotency_key,
        meta: {
          source: "pos_skus_controller",
          request_id: request.request_id
        }
      )

      after = sku_snapshot(sku.reload)

      log_pos_info(
        event: "pos.skus.freeze",
        sku_id: sku.id,
        sku: sku.code,
        idempotency_key: idempotency_key,
        result: result,
        before: before,
        after: after
      )

      render json: {
        ok: true,
        result: result,
        idempotency_key: idempotency_key,
        sku: serialize_sku(sku)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.skus.freeze.failed",
          err_class: e.class.name,
          err_message: e.message,
          sku_id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def unfreeze
      sku = Sku.find(params[:id])
      idempotency_key = params[:idempotency_key].presence || "ui:unfreeze:sku=#{sku.id}:#{Time.current.to_i}"

      before = sku_snapshot(sku)

      result = Inventory::Unfreeze.call!(
        sku: sku,
        idempotency_key: idempotency_key,
        meta: {
          source: "pos_skus_controller",
          request_id: request.request_id
        }
      )

      after = sku_snapshot(sku.reload)

      log_pos_info(
        event: "pos.skus.unfreeze",
        sku_id: sku.id,
        sku: sku.code,
        idempotency_key: idempotency_key,
        result: result,
        before: before,
        after: after
      )

      render json: {
        ok: true,
        result: result,
        idempotency_key: idempotency_key,
        sku: serialize_sku(sku)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "SKU not found" }, status: :not_found
    rescue ArgumentError => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error(
        {
          event: "pos.skus.unfreeze.failed",
          err_class: e.class.name,
          err_message: e.message,
          sku_id: params[:id]
        }.to_json
      )

      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def filtered_scope
      scope = Sku.all
      scope = scope.where(active: true) unless active_only_false?

      if params[:barcode].present?
        scope = scope.where(barcode: params[:barcode].to_s.strip)
      end

      if params[:sku_code].present?
        scope = scope.where(code: params[:sku_code].to_s.strip)
      end

      if params[:brand].present?
        scope = scope.where(brand: params[:brand].to_s.strip)
      end

      if params[:model].present?
        scope = scope.where(model: params[:model].to_s.strip)
      end

      if params[:color].present?
        scope = scope.where(color: params[:color].to_s.strip)
      end

      if params[:size].present?
        scope = scope.where(size: params[:size].to_s.strip)
      end

      apply_q_filter(scope)
    end

    def apply_q_filter(scope)
      return scope unless params[:q].present?

      q = "%#{sanitize_sql_like(params[:q].to_s.strip)}%"

      scope.where(
        <<~SQL.squish,
          code ILIKE :q
          OR barcode ILIKE :q
          OR brand ILIKE :q
          OR model ILIKE :q
          OR color ILIKE :q
          OR size ILIKE :q
        SQL
        q: q
      )
    end

    def distinct_values(scope, column_name)
      scope
        .where.not(column_name => [ nil, "" ])
        .distinct
        .order(column_name)
        .pluck(column_name)
    end

    def serialize_sku(sku)
      b = sku.inventory_balance

      shops = sku.sku_mappings
        .map(&:shop)
        .compact
        .uniq(&:id)

      shop_labels = shops
        .map { |shop| canonical_shop_label(shop) }
        .compact
        .uniq
        .sort

      {
        id: sku.id,
        code: sku.code,
        barcode: sku.barcode,
        barcode_bound: sku.barcode.present?,
        barcode_needs_binding: sku.barcode.blank?,
        brand: sku.brand,
        model: sku.model,
        color: sku.color,
        size: sku.size,
        active: sku.active,
        buffer_quantity: sku.buffer_quantity,
        store_available: sku.store_available,
        online_available: sku.online_available,
        on_hand: b&.on_hand || 0,
        reserved: b&.reserved || 0,
        frozen: b&.frozen_now? || false,
        freeze_reason: b&.freeze_reason,
        channel_shops: shop_labels,
        channel_shop_count: shop_labels.size
      }
    end

    def serialize_ledger_sku(sku)
      data = serialize_sku(sku)
      balance = sku.inventory_balance

      data.merge(
        stock_identity_id: sku.stock_identity_id,
        on_hand: balance&.on_hand.to_i,
        reserved: balance&.reserved.to_i,
        store_available: sku.store_available,
        online_available: sku.online_available,
        frozen: balance&.frozen_now? || false,
        frozen_at: balance&.frozen_at&.iso8601,
        frozen_at_th: format_bangkok_time(balance&.frozen_at),
        freeze_reason: balance&.freeze_reason,
        last_pushed_available: balance&.last_pushed_available,
        last_pushed_at: balance&.last_pushed_at&.iso8601,
        last_pushed_at_th: format_bangkok_time(balance&.last_pushed_at),
        group_members: ledger_group_members(sku)
      )
    end

    def ledger_group_members(sku)
      return [] if sku.stock_identity_id.blank?

      Sku
        .where(stock_identity_id: sku.stock_identity_id)
        .order(:code)
        .limit(30)
        .map do |member|
          {
            id: member.id,
            code: member.code,
            barcode: member.barcode,
            active: member.active
          }
        end
    end

    def canonical_shop_label(shop)
      return nil if shop.blank?

      code = shop.shop_code.to_s.strip
      code_downcase = code.downcase
      name = shop.name.to_s.strip

      # TikTok
      return "TikTok 1" if code == "THLCJ4W23M"
      return "TikTok 2" if code == "THLCM7WX8H"

      return "TikTok 1" if code_downcase == "tiktok_1"
      return "TikTok 2" if code_downcase == "tiktok_2"

      return "TikTok 1" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 1").zero?
      return "TikTok 2" if code_downcase.start_with?("tiktok_shop_") && name.casecmp("Tiktok 2").zero?

      return "TikTok 1" if name.casecmp("Thailumlongshop II").zero?
      return "TikTok 2" if name.casecmp("Young smile shoes").zero?

      # Lazada
      return "Lazada 1" if code == "THJ2HAHL"
      return "Lazada 2" if code == "TH1JHM87NL"

      return "Lazada 1" if code_downcase == "lazada_1"
      return "Lazada 2" if code_downcase == "lazada_2"

      # production จริงตอนนี้เป็น lazada_shop_<seller_id>
      return "Lazada 1" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 1").zero?
      return "Lazada 2" if code_downcase.start_with?("lazada_shop_") && name.casecmp("Lazada 2").zero?

      # fallback ตามชื่อ
      return "Lazada 1" if name.casecmp("Thai Lumlong Shop").zero?
      return "Lazada 2" if name.casecmp("Thai Lumlong Shop II").zero?
      return "Lazada 1" if name.casecmp("Lazada 1").zero?
      return "Lazada 2" if name.casecmp("Lazada 2").zero?

      # Shopee / POS
      return "Shopee" if code_downcase.start_with?("shopee")
      return "Shopee" if name.downcase.start_with?("shopee")
      return "POS" if code_downcase == "pos" || code_downcase.start_with?("pos")

      code.presence || name.presence
    end

    def serialize_inventory_action(action)
      order_line = action.order_line
      order = order_line&.order
      shop = order&.shop
      meta = action.meta.to_h

      {
        source_type: "inventory_action",
        id: action.id,
        occurred_at: action.created_at&.iso8601,
        occurred_at_th: format_bangkok_time(action.created_at),
        day_group: ledger_day_group(action.created_at),
        action_type: action.action_type,
        action_label: human_ledger_action(action.action_type),
        quantity: action.quantity,
        delta_on_hand: inferred_action_delta_on_hand(action),
        delta_reserved: inferred_action_delta_reserved(action),
        delta_label: ledger_delta_label(action),
        severity: ledger_action_severity(action),
        order_line_id: action.order_line_id,
        idempotency_key: action.idempotency_key,
        idempotency_key_short: shorten_key(action.idempotency_key),
        meta: meta,
        extracted_meta: extract_ledger_meta(meta),
        order_line: order_line && {
          id: order_line.id,
          external_sku: order_line.external_sku,
          external_line_id: order_line.external_line_id,
          quantity: order_line.quantity,
          status: order_line.status
        },
        order: order && {
          id: order.id,
          external_order_id: order.external_order_id,
          channel: order.channel,
          status: order.status,
          shop_id: order.shop_id,
          shop_label: canonical_shop_label(shop)
        }
      }
    end

    def serialize_stock_movement(movement)
      meta = movement.meta.to_h

      {
        source_type: "stock_movement",
        id: movement.id,
        occurred_at: movement.created_at&.iso8601,
        occurred_at_th: format_bangkok_time(movement.created_at),
        day_group: ledger_day_group(movement.created_at),
        reason: movement.reason,
        action_label: movement.reason.to_s.presence || "Stock movement",
        delta_on_hand: movement.delta_on_hand,
        delta_reserved: 0,
        delta_label: "On hand #{signed_number(movement.delta_on_hand.to_i)}",
        severity: movement.delta_on_hand.to_i.negative? ? "warning" : "success",
        meta: meta,
        extracted_meta: extract_ledger_meta(meta)
      }
    end

    def inferred_action_delta_on_hand(action)
      case action.action_type
      when "commit"
        -action.quantity.to_i
      when "return_scan", "stock_in"
        action.quantity.to_i
      when "stock_adjust"
        stock_adjust_delta(action)
      when "reserve", "release"
        0
      else
        nil
      end
    end

    def inferred_action_delta_reserved(action)
      case action.action_type
      when "reserve"
        action.quantity.to_i
      when "release", "commit"
        -action.quantity.to_i
      else
        0
      end
    end

    def ledger_delta_label(action)
      on_hand = inferred_action_delta_on_hand(action)
      reserved = inferred_action_delta_reserved(action)

      parts = []
      parts << "On hand #{signed_number(on_hand)}" unless on_hand.nil? || on_hand.zero?
      parts << "Reserved #{signed_number(reserved)}" unless reserved.nil? || reserved.zero?

      return "No stock delta" if parts.empty?

      parts.join(" / ")
    end

    def ledger_action_severity(action)
      meta = action.meta.to_h

      return "danger" if meta["shortfall"].present?
      return "danger" if action.action_type == "commit"
      return "warning" if action.action_type == "stock_adjust"
      return "success" if %w[release return_scan stock_in].include?(action.action_type)
      return "info" if action.action_type == "reserve"

      "neutral"
    end

    def human_ledger_action(action_type)
      case action_type.to_s
      when "reserve"
        "Reserve"
      when "release"
        "Release"
      when "commit"
        "Commit"
      when "return_scan"
        "Return scan"
      when "stock_in"
        "Stock in"
      when "stock_adjust"
        "Stock adjust"
      else
        action_type.to_s.humanize
      end
    end

    def extract_ledger_meta(meta)
      keys = %w[
        source
        mode
        adjust_mode
        set_to
        delta
        shortfall
        request_id
        buffer_quantity
        scan_input
        scan_match_type
        return_shipment_id
        return_shipment_line_id
        previous_status
        status
        trigger
        reason
        barcode
        quantity
      ]

      keys.each_with_object({}) do |key, out|
        value = meta[key]
        out[key] = value if value.present?
      end
    end

    def stock_adjust_delta(action)
      meta = action.meta.to_h

      return meta["delta"].to_i if meta["delta"].present?

      nil
    end

    def format_bangkok_time(time)
      return nil if time.blank?

      time.in_time_zone("Asia/Bangkok").strftime("%d %b %Y %H:%M ICT")
    end

    def ledger_day_group(time)
      return "-" if time.blank?

      date = time.in_time_zone("Asia/Bangkok").to_date
      today = Time.current.in_time_zone("Asia/Bangkok").to_date

      return "Today" if date == today
      return "Yesterday" if date == today - 1.day

      date.strftime("%d %b %Y")
    end

    def shorten_key(key)
      raw = key.to_s
      return nil if raw.blank?
      return raw if raw.length <= 34

      "#{raw.first(18)}...#{raw.last(12)}"
    end

    def signed_number(value)
      return nil if value.nil?

      n = value.to_i
      n.positive? ? "+#{n}" : n.to_s
    end

    def sku_snapshot(sku)
      balance = sku.inventory_balance

      {
        sku_id: sku.id,
        sku: sku.code,
        on_hand: balance&.on_hand || 0,
        reserved: balance&.reserved || 0,
        store_available: sku.store_available,
        online_available: sku.online_available,
        frozen: balance&.frozen_now? || false,
        freeze_reason: balance&.freeze_reason
      }
    end

    def current_filters
      {
        barcode: params[:barcode].presence,
        sku_code: params[:sku_code].presence,
        brand: params[:brand].presence,
        model: params[:model].presence,
        color: params[:color].presence,
        size: params[:size].presence,
        q: params[:q].presence,
        active_only: !active_only_false?
      }.compact
    end

    def normalized_limit
      raw = params[:limit].to_i
      return 50 if raw <= 0
      return 200 if raw > 200

      raw
    end

    def normalized_ledger_limit
      raw = params[:limit].to_i
      return 100 if raw <= 0
      return 300 if raw > 300

      raw
    end

    def truthy_param_default_true?(key)
      return true if params[key].nil?

      ActiveModel::Type::Boolean.new.cast(params[key])
    end

    def active_only_false?
      ActiveModel::Type::Boolean.new.cast(params[:active_only]) == false
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end
  end
end

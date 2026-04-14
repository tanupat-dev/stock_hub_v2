# frozen_string_literal: true

module Orders
  class ApplyInventoryPolicy
    # Policy layer for ONLINE orders (marketplace).
    #
    # Goals:
    # - polling-only friendly (idempotent keys)
    # - debug-friendly (before/after snapshots)
    # - structured logging (JSON)
    # - ONLINE availability only (Sku#online_available); POS/store handled elsewhere
    #
    # NOTE:
    # - freeze (InventoryBalance#frozen_at) is marketplace-only gate.
    # - POS must never be blocked by freeze; this service is not used for POS.

    VALID_ACTIONS = %i[reserve commit release].freeze

    def self.call!(order:, action: nil, line_actions: nil, idempotency_prefix:, meta: {})
      new(order:, action:, line_actions:, idempotency_prefix:, meta:).call!
    end

    def initialize(order:, action:, line_actions:, idempotency_prefix:, meta:)
      @order = order
      @action = action&.to_sym
      @line_actions = line_actions
      @idempotency_prefix = idempotency_prefix
      @meta = meta || {}
      @policy_run_id = SecureRandom.hex(8)
    end

    def call!
      validate_idempotency_prefix!
      actions = build_actions!
      results = []

      # Prefer shop as source of truth (order.channel might diverge)
      shop = @order.shop
      shop_channel = shop&.channel || @order.channel

      actions.each do |entry|
        line = entry.fetch(:order_line)
        action = entry.fetch(:action).to_sym

        unless VALID_ACTIONS.include?(action)
          results << {
            order_line_id: line.id,
            action: action,
            result: :invalid_action
          }
          next
        end

        sku = line.sku
        if sku.nil?
          results << {
            order_line_id: line.id,
            action: action,
            result: :missing_sku
          }
          next
        end

        qty = (line.quantity.presence || 1).to_i
        qty = 1 if qty <= 0

        # Reduce repeated reloads: take an initial snapshot and pass through.
        before = snapshot(sku)

        case action
        when :reserve
          results << apply_reserve!(line:, sku:, qty:, before:, shop_channel:)
        when :commit
          results << apply_commit!(line:, sku:, qty:, before:, shop_channel:)
        when :release
          results << apply_release!(line:, sku:, qty:, before:, shop_channel:)
        end
      end

      {
        ok: true,
        policy_run_id: @policy_run_id,
        order_id: @order.id,
        channel: shop_channel,
        shop_id: @order.shop_id,
        external_order_id: @order.external_order_id,
        status: @order.status,
        results: results
      }
    end

    private

    # ---- action builders ----

    def build_actions!
      if @line_actions.present?
        @line_actions.map do |h|
          {
            order_line: h.fetch(:order_line),
            action: h.fetch(:action).to_sym
          }
        end
      else
        raise ArgumentError, "action is required when line_actions not provided" if @action.nil?

        @order.order_lines.map do |line|
          { order_line: line, action: @action }
        end
      end
    end

    # ---- idempotency ----

    def idem_key(line, suffix)
      raise ArgumentError, "order_line is required" if line.nil?
      raise ArgumentError, "order_line id is required" if line.id.blank?

      suffix_value = suffix.to_s.strip
      raise ArgumentError, "suffix is required" if suffix_value.blank?

      key = "#{@idempotency_prefix}:line:#{line.id}:#{suffix_value}"

      if @order.channel.to_s == "shopee" && (key.include?("shoopee") || key.include?("orrder"))
        raise ArgumentError, "suspicious shopee idempotency key: #{key}"
      end

      key
    end

    def validate_idempotency_prefix!
      prefix = @idempotency_prefix.to_s

      raise ArgumentError, "idempotency_prefix is required" if prefix.blank?

      if @order.channel.to_s == "shopee"
        Orders::Shopee::Idempotency.validate_policy_prefix!(prefix)
      end
    end

    # ---- snapshots ----

    def snapshot(sku)
      b = sku.inventory_balance&.reload
      {
        sku: {
          id: sku.id,
          code: sku.code,
          barcode: sku.barcode,
          buffer_quantity: sku.buffer_quantity
        },
        balance: b ? {
          on_hand: b.on_hand,
          reserved: b.reserved,
          frozen_at: b.frozen_at,
          freeze_reason: b.freeze_reason,
          last_pushed_available: b.last_pushed_available,
          last_pushed_at: b.last_pushed_at
        } : nil,
        # store_available included for visibility only (POS truth),
        # but decisions in this service must use ONLINE rules.
        store_available: sku.store_available,
        online_available: sku.online_available
      }
    end

    # ---- logging ----

    def log_info(payload)
      event = payload[:event]

      # ✅ log เฉพาะสำคัญ
      return unless [
        "orders.apply_inventory.commit.done",
        "orders.apply_inventory.reserve",
        "orders.apply_inventory.release"
      ].include?(event)

      Rails.logger.info(payload.to_json)
    end

    def log_error(payload)
      Rails.logger.error(payload.to_json)
    end

    def base_log(payload)
      {
        policy_run_id: @policy_run_id,
        order_id: @order.id,
        order_line_id: payload[:order_line_id],
        shop_id: @order.shop_id,
        external_order_id: @order.external_order_id
      }.merge(payload)
    end

    # ---- apply actions ----

    def apply_reserve!(line:, sku:, qty:, before:, shop_channel:)
      idk = idem_key(line, "reserve")

      res = Inventory::Reserve.call!(
        sku: sku,
        quantity: qty,
        idempotency_key: idk,
        meta: base_meta(shop_channel:).merge(@meta).merge(source: "orders_apply_policy", action: "reserve"),
        order_line: line
      )

      after = snapshot(sku)

      log_info(
        base_log(
          event: "orders.apply_inventory.reserve",
          order_line_id: line.id,
          channel: shop_channel,
          sku: sku.code,
          quantity: qty,
          idempotency_key: idk,
          result: res,
          before: before,
          after: after
        )
      )

      enqueue_stock_sync_for_marketplace(sku, shop_channel) if [ :reserved, :already_applied ].include?(res)

      {
        order_line_id: line.id,
        action: :reserve,
        result: res,
        idempotency_key: idk,
        before: before,
        after: after
      }
    end

    def apply_release!(line:, sku:, qty:, before:, shop_channel:)
      idk = idem_key(line, "release")

      res = Inventory::Release.call!(
        sku: sku,
        quantity: qty,
        idempotency_key: idk,
        meta: base_meta(shop_channel:).merge(@meta).merge(source: "orders_apply_policy", action: "release"),
        order_line: line
      )

      after = snapshot(sku)

      log_info(
        base_log(
          event: "orders.apply_inventory.release",
          order_line_id: line.id,
          channel: shop_channel,
          sku: sku.code,
          quantity: qty,
          idempotency_key: idk,
          result: res,
          before: before,
          after: after
        )
      )

      enqueue_stock_sync_for_marketplace(sku, shop_channel) if [ :released, :already_applied ].include?(res)

      {
        order_line_id: line.id,
        action: :release,
        result: res,
        idempotency_key: idk,
        before: before,
        after: after
      }
    end

    def apply_commit!(line:, sku:, qty:, before:, shop_channel:)
      commit_idk = idem_key(line, "commit")

      reserved_for_line = reserved_qty_for_line(line)
      balance_before_commit = sku.inventory_balance&.reload
      reserved_now = balance_before_commit&.reserved.to_i

      if reserved_for_line < qty
        after_blocked = snapshot(sku)

        log_error(
          base_log(
            event: "orders.apply_inventory.commit.blocked",
            order_line_id: line.id,
            channel: shop_channel,
            sku: sku.code,
            quantity: qty,
            error_reason: "no_prior_line_reserve",
            reserved_now: reserved_now,
            reserved_for_line: reserved_for_line,
            commit_idempotency_key: commit_idk,
            before: before,
            after: after_blocked
          )
        )

        return {
          order_line_id: line.id,
          action: :commit,
          result: :blocked_no_prior_line_reserve,
          reserved_now: reserved_now,
          reserved_for_line: reserved_for_line,
          commit_idempotency_key: commit_idk,
          before: before,
          after: after_blocked
        }
      end

      commit_res = Inventory::Commit.call!(
        sku: sku,
        quantity: qty,
        idempotency_key: commit_idk,
        meta: base_meta(shop_channel:).merge(@meta).merge(source: "orders_apply_policy", action: "commit"),
        order_line: line
      )

      after_commit = snapshot(sku)

      payload = base_log(
        event: "orders.apply_inventory.commit.done",
        order_line_id: line.id,
        channel: shop_channel,
        sku: sku.code,
        quantity: qty,
        commit_result: commit_res,
        commit_idempotency_key: commit_idk,
        reserved_now: reserved_now,
        reserved_for_line: reserved_for_line,
        before: before,
        after: after_commit
      )

      if before.dig(:balance, :frozen_at).present? || after_commit.dig(:balance, :frozen_at).present?
        payload[:note] = "frozen_state_present_during_commit"
      end

      log_info(payload)

      enqueue_stock_sync_for_marketplace(sku, shop_channel) if [ :committed, :already_applied ].include?(commit_res)

      {
        order_line_id: line.id,
        action: :commit,
        result: commit_res,
        commit_idempotency_key: commit_idk,
        reserved_now: reserved_now,
        reserved_for_line: reserved_for_line,
        before: before,
        after: after_commit
      }
    rescue Inventory::Commit::OnHandWouldGoNegative => e
      after_fail = snapshot(sku)

      log_error(
        base_log(
          event: "orders.apply_inventory.commit.fail",
          order_line_id: line.id,
          channel: shop_channel,
          sku: sku.code,
          quantity: qty,
          err_class: e.class.name,
          err_message: e.message,
          before: before,
          after: after_fail
        )
      )

      {
        order_line_id: line.id,
        action: :commit,
        result: :commit_failed_on_hand_negative,
        error: "#{e.class}: #{e.message}",
        commit_idempotency_key: commit_idk,
        before: before,
        after: after_fail
      }
    end

    def reserved_qty_for_line(line)
      reserved =
        InventoryAction
          .where(order_line_id: line.id, action_type: "reserve")
          .sum(:quantity)

      released =
        InventoryAction
          .where(order_line_id: line.id, action_type: "release")
          .sum(:quantity)

      committed =
        InventoryAction
          .where(order_line_id: line.id, action_type: "commit")
          .sum(:quantity)

      reserved - released - committed
    end

    def base_meta(shop_channel:)
      {
        channel: shop_channel,
        shop_id: @order.shop_id,
        external_order_id: @order.external_order_id,
        order_id: @order.id
      }
    end

    def enqueue_stock_sync_for_marketplace(sku, shop_channel)
      return if shop_channel == "pos"

      StockSync::RequestDebouncer.call!(
        sku: sku,
        reason: "orders_apply_policy"
      )
    end
  end
end

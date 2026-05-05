# frozen_string_literal: true

module Orders
  class RepairMissingInventoryActions
    # Repairs ONLINE marketplace order lines that already have sku_id,
    # but were not covered by inventory policy because the line/SKU was
    # attached after the first policy run.
    #
    # Safe behavior:
    # - Reservable statuses: reserve missing-action lines.
    # - IN_TRANSIT: commit only lines that already have an open reserve.
    # - IN_TRANSIT with no prior reserve: log repair_required, do not commit.
    # - Terminal/noop statuses: do nothing.
    #
    # This is intentionally conservative. It prevents future silent misses,
    # but does not invent a prior reserve for shipped lines.

    def self.call!(order:, raw_order: nil, previous_status: nil, source:)
      new(
        order: order,
        raw_order: raw_order,
        previous_status: previous_status,
        source: source
      ).call!
    end

    def initialize(order:, raw_order:, previous_status:, source:)
      @order = order
      @raw_order = raw_order || {}
      @previous_status = previous_status.to_s.presence
      @source = source.to_s.presence || "repair_missing_inventory_actions"
      @repair_run_id = SecureRandom.hex(8)
    end

    def call!
      @order.reload

      status = @order.status.to_s
      lines = mapped_lines

      result =
        if Orders::StatusTransitionGuard.reservable_status?(status)
          repair_reservable_lines!(lines, status)
        elsif status == "IN_TRANSIT"
          repair_in_transit_lines!(lines, status)
        else
          {
            action: nil,
            reason: "status_not_repairable",
            status: status,
            lines_checked: lines.size
          }
        end

      payload = {
        ok: true,
        repair_run_id: @repair_run_id,
        order_id: @order.id,
        channel: @order.channel,
        shop_id: @order.shop_id,
        external_order_id: @order.external_order_id,
        status: status,
        previous_status: @previous_status,
        source: @source
      }.merge(result)

      log_info(
        payload.merge(
          event: "orders.repair_missing_inventory_actions.done"
        )
      )

      payload
    end

    private

    def mapped_lines
      @order
        .order_lines
        .includes(:sku)
        .order(:id)
        .select { |line| line.sku_id.present? && line.sku.present? }
    end

    def repair_reservable_lines!(lines, status)
      candidates = lines.select { |line| missing_all_inventory_actions?(line) }

      if candidates.blank?
        return {
          action: nil,
          reason: "no_missing_reserve_lines",
          status: status,
          lines_checked: lines.size,
          candidate_line_ids: []
        }
      end

      result = apply_line_actions!(
        candidates.map { |line| { order_line: line, action: :reserve } },
        status: status,
        repair_action: "reserve_missing_line"
      )

      {
        action: :reserve,
        reason: "reserved_missing_lines",
        status: status,
        lines_checked: lines.size,
        candidate_line_ids: candidates.map(&:id),
        apply_result: result
      }
    end

    def repair_in_transit_lines!(lines, status)
      commit_candidates =
        lines.select do |line|
          open_reserved_qty_for_line(line) >= quantity_for(line) &&
            committed_qty_for_line(line) < quantity_for(line)
        end

      missing_prior_reserve =
        lines.select { |line| missing_all_inventory_actions?(line) }

      apply_result = nil

      if commit_candidates.any?
        apply_result = apply_line_actions!(
          commit_candidates.map { |line| { order_line: line, action: :commit } },
          status: status,
          repair_action: "commit_existing_open_reserve"
        )
      end

      if missing_prior_reserve.any?
        log_warn(
          event: "orders.repair_missing_inventory_actions.repair_required",
          repair_run_id: @repair_run_id,
          reason: "in_transit_line_without_prior_reserve",
          order_id: @order.id,
          channel: @order.channel,
          shop_id: @order.shop_id,
          external_order_id: @order.external_order_id,
          status: status,
          previous_status: @previous_status,
          source: @source,
          line_ids: missing_prior_reserve.map(&:id),
          lines: missing_prior_reserve.map { |line| line_log_payload(line) }
        )
      end

      {
        action: :commit,
        reason: "in_transit_repair_checked",
        status: status,
        lines_checked: lines.size,
        commit_candidate_line_ids: commit_candidates.map(&:id),
        missing_prior_reserve_line_ids: missing_prior_reserve.map(&:id),
        apply_result: apply_result
      }
    end

    def apply_line_actions!(line_actions, status:, repair_action:)
      return nil if line_actions.blank?

      Orders::ApplyInventoryPolicy.call!(
        order: @order,
        line_actions: line_actions,
        idempotency_prefix: idempotency_prefix,
        meta: {
          source: @source,
          repair_action: repair_action,
          status: status,
          previous_status: @previous_status,
          update_time: @raw_order["update_time"],
          repair_run_id: @repair_run_id
        }
      )
    end

    def idempotency_prefix
      case @order.channel.to_s
      when "shopee"
        Orders::Shopee::Idempotency.policy_prefix(@order.external_order_id)
      else
        "#{@order.channel}:order:#{@order.external_order_id}"
      end
    end

    def missing_all_inventory_actions?(line)
      InventoryAction
        .where(order_line_id: line.id, action_type: %w[reserve commit release])
        .none?
    end

    def open_reserved_qty_for_line(line)
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

      reserved.to_i - released.to_i - committed.to_i
    end

    def committed_qty_for_line(line)
      InventoryAction
        .where(order_line_id: line.id, action_type: "commit")
        .sum(:quantity)
        .to_i
    end

    def quantity_for(line)
      qty = line.quantity.to_i
      qty.positive? ? qty : 1
    end

    def line_log_payload(line)
      sku = line.sku
      balance = sku&.inventory_balance

      {
        order_line_id: line.id,
        external_line_id: line.external_line_id,
        external_sku: line.external_sku,
        sku_id: sku&.id,
        sku: sku&.code,
        quantity: quantity_for(line),
        open_reserved_qty: open_reserved_qty_for_line(line),
        committed_qty: committed_qty_for_line(line),
        balance: balance ? {
          id: balance.id,
          on_hand: balance.on_hand,
          reserved: balance.reserved,
          frozen_at: balance.frozen_at,
          freeze_reason: balance.freeze_reason
        } : nil
      }
    end

    def log_info(payload)
      Rails.logger.info(payload.to_json)
    end

    def log_warn(payload)
      Rails.logger.warn(payload.to_json)
    end
  end
end

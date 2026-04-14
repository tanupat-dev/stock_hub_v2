# frozen_string_literal: true

module Inventory
  class OversellGuard
    def self.call!(sku:, trigger:, idempotency_key:, meta: {})
      new(sku:, trigger:, idempotency_key:, meta:).call!
    end

    def initialize(sku:, trigger:, idempotency_key:, meta:)
      @sku = sku
      @trigger = trigger.to_s.presence || "unknown"
      @idempotency_key = idempotency_key.to_s
      @meta = (meta || {}).deep_dup
    end

    def call!
      raise ArgumentError, "sku is required" if @sku.nil?
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      incident = nil
      result = :ok
      shortfall = 0
      before = nil
      after = nil
      should_enqueue_force_zero = false

      OversellIncident.transaction do
        balance = Inventory::BalanceFetcher.fetch_for_update!(sku: @sku)

        before = snapshot(balance)
        shortfall = balance.reserved.to_i - balance.on_hand.to_i

        if shortfall <= 0
          after = snapshot(balance)
          result = :ok
          next
        end

        if !balance.frozen_now? || balance.freeze_reason.to_s != "oversold"
          balance.update!(
            frozen_at: Time.current,
            freeze_reason: "oversold"
          )
        end

        incident = OversellIncident.where(sku_id: @sku.id, status: "open").order(created_at: :desc, id: :desc).first

        if incident.nil?
          incident = OversellIncident.create!(
            sku: @sku,
            shortfall_qty: shortfall,
            trigger: @trigger,
            status: "open",
            idempotency_key: @idempotency_key,
            meta: incident_meta.merge(rule: "fifo_by_first_reserve")
          )

          allocations = Inventory::OversellAllocator.call!(sku: @sku, shortfall_qty: shortfall)

          allocations.each do |allocation|
            OversellAllocation.create!(
              oversell_incident: incident,
              sku: @sku,
              order_line_id: allocation.fetch(:order_line_id),
              quantity: allocation.fetch(:qty),
              meta: { rule: "fifo_by_first_reserve" }
            )
          end

          result = :incident_created
        else
          incident.update!(
            shortfall_qty: shortfall,
            trigger: @trigger,
            meta: incident.meta.to_h.merge(incident_meta)
          )

          incident.oversell_allocations.delete_all

          allocations = Inventory::OversellAllocator.call!(sku: @sku, shortfall_qty: shortfall)

          allocations.each do |allocation|
            OversellAllocation.create!(
              oversell_incident: incident,
              sku: @sku,
              order_line_id: allocation.fetch(:order_line_id),
              quantity: allocation.fetch(:qty),
              meta: { rule: "fifo_by_first_reserve" }
            )
          end

          result = :incident_reused
        end

        after = snapshot(balance)
        should_enqueue_force_zero = true
      end

      if should_enqueue_force_zero && incident.present?
        ForceOversellZeroJob.perform_later(incident.id)
      end

      Rails.logger.warn(
        {
          event: "inventory.oversell_guard",
          sku_id: @sku.id,
          sku: @sku.code,
          trigger: @trigger,
          idempotency_key: @idempotency_key,
          result: result,
          shortfall_qty: shortfall,
          oversell_incident_id: incident&.id,
          meta: @meta,
          before: before,
          after: after,
          enqueued_force_zero_job: should_enqueue_force_zero
        }.compact.to_json
      )

      {
        ok: true,
        result: result,
        oversell_incident_id: incident&.id,
        shortfall_qty: shortfall,
        enqueued_force_zero_job: should_enqueue_force_zero
      }
    end

    private

    def incident_meta
      {
        source_meta: @meta,
        guard_trigger: @trigger,
        guard_idempotency_key: @idempotency_key
      }
    end

    def snapshot(balance)
      {
        on_hand: balance.on_hand,
        reserved: balance.reserved,
        frozen_at: balance.frozen_at,
        freeze_reason: balance.freeze_reason,
        raw_available: balance.raw_available,
        store_available: balance.store_available,
        online_available_if_unfrozen: balance.online_available(buffer_quantity: @sku.buffer_quantity)
      }
    end
  end
end

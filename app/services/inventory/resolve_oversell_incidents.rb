# frozen_string_literal: true

module Inventory
  class ResolveOversellIncidents
    def self.call!(sku:, trigger: nil, meta: {})
      new(sku:, trigger:, meta:).call!
    end

    def initialize(sku:, trigger:, meta:)
      @sku = sku
      @trigger = trigger.to_s.presence
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "sku is required" if @sku.nil?

      balance = @sku.inventory_balance
      return :no_balance if balance.nil?

      if balance.on_hand.to_i < balance.reserved.to_i
        log(:still_oversold, resolved_count: 0)
        return :still_oversold
      end

      incidents = OversellIncident.where(sku_id: @sku.id, status: "open").to_a
      return :no_open_incidents if incidents.empty?

      now = Time.current

      OversellIncident.transaction do
        incidents.each do |incident|
          incident.update!(
            status: "resolved",
            resolved_at: now,
            meta: incident.meta.to_h.merge(
              resolved_by_trigger: @trigger,
              resolved_meta: @meta
            )
          )
        end
      end

      log(:resolved, resolved_count: incidents.size)

      :resolved
    end

    private

    def log(result, resolved_count:)
      Rails.logger.info(
        {
          event: "inventory.resolve_oversell_incidents",
          sku_id: @sku.id,
          sku: @sku.code,
          trigger: @trigger,
          result: result,
          resolved_count: resolved_count,
          meta: @meta
        }.compact.to_json
      )
    end
  end
end

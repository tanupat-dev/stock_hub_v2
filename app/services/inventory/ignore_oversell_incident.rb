# frozen_string_literal: true

module Inventory
  class IgnoreOversellIncident
    def self.call!(oversell_incident:, idempotency_key:, meta: {})
      new(oversell_incident:, idempotency_key:, meta:).call!
    end

    def initialize(oversell_incident:, idempotency_key:, meta:)
      @oversell_incident = oversell_incident
      @idempotency_key = idempotency_key.to_s
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "oversell_incident is required" if @oversell_incident.nil?
      raise ArgumentError, "idempotency_key is required" if @idempotency_key.blank?

      OversellIncident.transaction do
        @oversell_incident.lock!
        @oversell_incident.reload

        return @oversell_incident if replay?
        return @oversell_incident if @oversell_incident.status == "ignored"

        @oversell_incident.update!(
          status: "ignored",
          resolved_at: Time.current,
          meta: @oversell_incident.meta.to_h.merge(
            "manual_ignore_idempotency_key" => @idempotency_key,
            "manual_ignore_meta" => @meta
          )
        )

        Rails.logger.warn(
          {
            event: "inventory.ignore_oversell_incident",
            oversell_incident_id: @oversell_incident.id,
            sku_id: @oversell_incident.sku_id,
            sku: @oversell_incident.sku.code,
            idempotency_key: @idempotency_key,
            meta: @meta
          }.to_json
        )

        @oversell_incident
      end
    end

    private

    def replay?
      @oversell_incident.meta.to_h["manual_ignore_idempotency_key"] == @idempotency_key
    end
  end
end

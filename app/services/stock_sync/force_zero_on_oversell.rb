# frozen_string_literal: true

module StockSync
  class ForceZeroOnOversell
    def self.call!(oversell_incident:)
      new(oversell_incident:).call!
    end

    def initialize(oversell_incident:)
      @oversell_incident = oversell_incident
      @sku = oversell_incident.sku
    end

    def call!
      raise ArgumentError, "oversell_incident is required" if @oversell_incident.nil?
      raise ArgumentError, "sku is required" if @sku.nil?

      reason = "oversell_incident:#{@oversell_incident.id}"

      Rails.logger.warn(
        {
          event: "stock_sync.oversell_force_zero.start",
          oversell_incident_id: @oversell_incident.id,
          sku_id: @sku.id,
          sku: @sku.code,
          reason: reason
        }.to_json
      )

      available = StockSync::PushSku.call!(
        sku: @sku,
        reason: reason,
        force: true
      )

      manual_zero_required_channels = active_manual_channels

      merge_incident_meta!(
        force_zero_requested_at: Time.current.iso8601,
        force_zero_reason: reason,
        force_zero_result: "requested",
        force_zero_available_sent: available.to_i,
        manual_zero_required_channels: manual_zero_required_channels
      )

      Rails.logger.warn(
        {
          event: "stock_sync.oversell_force_zero.done",
          oversell_incident_id: @oversell_incident.id,
          sku_id: @sku.id,
          sku: @sku.code,
          reason: reason,
          available_sent: available.to_i,
          manual_zero_required_channels: manual_zero_required_channels
        }.to_json
      )

      {
        ok: true,
        oversell_incident_id: @oversell_incident.id,
        available_sent: available.to_i,
        manual_zero_required_channels: manual_zero_required_channels
      }
    rescue => e
      merge_incident_meta!(
        force_zero_requested_at: Time.current.iso8601,
        force_zero_reason: "oversell_incident:#{@oversell_incident.id}",
        force_zero_result: "failed",
        force_zero_error: "#{e.class}: #{e.message}"
      )

      Rails.logger.error(
        {
          event: "stock_sync.oversell_force_zero.fail",
          oversell_incident_id: @oversell_incident.id,
          sku_id: @sku.id,
          sku: @sku.code,
          err_class: e.class.name,
          err_message: e.message
        }.to_json
      )
      raise
    end

    private

    def active_manual_channels
      @sku.sku_mappings
          .joins(:shop)
          .merge(Shop.where(active: true, channel: "shopee"))
          .distinct
          .pluck("shops.channel")
          .uniq
    end

    def merge_incident_meta!(attrs)
      @oversell_incident.reload
      @oversell_incident.update_columns(
        meta: @oversell_incident.meta.to_h.merge(attrs),
        updated_at: Time.current
      )
    rescue StandardError
      nil
    end
  end
end

# frozen_string_literal: true

module Pos
  class OversellsController < BaseController
    def index
      scope = OversellIncident
        .includes(:sku, oversell_allocations: { order_line: :order })
        .order(created_at: :desc, id: :desc)

      if params[:status].present?
        scope = scope.where(status: params[:status].to_s.strip)
      end

      if params[:sku_code].present?
        scope = scope.joins(:sku).where(skus: { code: params[:sku_code].to_s.strip })
      end

      incidents = scope.limit(normalized_limit)

      render json: {
        ok: true,
        filters: current_filters,
        count: incidents.size,
        incidents: incidents.map { |incident| serialize(incident) }
      }
    end

    def show
      incident = OversellIncident
        .includes(:sku, oversell_allocations: { order_line: :order })
        .find(params[:id])

      render json: {
        ok: true,
        incident: serialize(incident)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "oversell incident not found" }, status: :not_found
    end

    def resolve
      incident = OversellIncident.find(params[:id])

      incident = Inventory::ResolveOversellIncident.call!(
        oversell_incident: incident,
        idempotency_key: params.require(:idempotency_key),
        meta: {
          source: "pos_api",
          note: params[:note].to_s.presence
        }
      )

      render json: {
        ok: true,
        incident: serialize(reload_incident(incident))
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "oversell incident not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    rescue Inventory::ResolveOversellIncident::IncidentStillOversold => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def ignore
      incident = OversellIncident.find(params[:id])

      incident = Inventory::IgnoreOversellIncident.call!(
        oversell_incident: incident,
        idempotency_key: params.require(:idempotency_key),
        meta: {
          source: "pos_api",
          note: params[:note].to_s.presence
        }
      )

      render json: {
        ok: true,
        incident: serialize(reload_incident(incident))
      }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "oversell incident not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { ok: false, error: e.message }, status: :bad_request
    end

    private

    def reload_incident(incident)
      OversellIncident
        .includes(:sku, oversell_allocations: { order_line: :order })
        .find(incident.id)
    end

    def serialize(incident)
      {
        id: incident.id,
        created_at: incident.created_at,
        resolved_at: incident.resolved_at,
        sku: {
          id: incident.sku.id,
          code: incident.sku.code,
          barcode: incident.sku.barcode
        },
        shortfall_qty: incident.shortfall_qty,
        trigger: incident.trigger,
        status: incident.status,
        meta: incident.meta,
        allocations: incident.oversell_allocations.map do |allocation|
          order_line = allocation.order_line
          order = order_line.order

          {
            oversell_allocation_id: allocation.id,
            order_line_id: order_line.id,
            order_id: order.id,
            external_order_id: order.external_order_id,
            channel: order.channel,
            quantity: allocation.quantity
          }
        end
      }
    end

    def normalized_limit
      raw = params[:limit].to_i
      return 100 if raw <= 0
      return 300 if raw > 300

      raw
    end

    def current_filters
      {
        status: params[:status].presence,
        sku_code: params[:sku_code].presence,
        limit: normalized_limit
      }.compact
    end
  end
end

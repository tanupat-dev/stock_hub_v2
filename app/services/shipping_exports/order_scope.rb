# app/services/shipping_exports/order_scope.rb
# frozen_string_literal: true

module ShippingExports
  class OrderScope
    ELIGIBLE_CHANNELS = %w[tiktok lazada shopee].freeze
    DEFAULT_STATUS = "AWAITING_FULFILLMENT"

    def self.call(filters: {})
      new(filters: filters).call
    end

    def initialize(filters:)
      @filters = (filters || {}).to_h.symbolize_keys
    end

    def call
      scope = Order
        .includes(:shop, order_lines: :sku)
        .joins(:shop)
        .where(channel: ELIGIBLE_CHANNELS)

      if filters[:status].present?
        normalized_status = normalize_status_filter(filters[:status])
        scope = scope.where(status: normalized_status) if normalized_status.present?
      else
        scope = scope.where(status: DEFAULT_STATUS)
      end

      scope = apply_status_guards(scope)

      scope = scope.order(updated_at_external: :desc, id: :desc)

      scope = apply_shop(scope)
      scope = apply_date_from(scope)
      scope = apply_date_to(scope)
      scope = apply_query(scope)

      scope
    end

    private

    attr_reader :filters

    def apply_shop(scope)
      return scope if filters[:shop].blank?

      shop_codes = normalize_shop_filter(filters[:shop])
      return scope.none if shop_codes.empty?

      scope.where(shops: { shop_code: shop_codes })
    end

    def apply_date_from(scope)
      return scope if filters[:date_from].blank?

      from = Date.parse(filters[:date_from].to_s)
      scope.where("COALESCE(orders.updated_at_external, orders.created_at) >= ?", from.beginning_of_day)
    end

    def apply_date_to(scope)
      return scope if filters[:date_to].blank?

      to = Date.parse(filters[:date_to].to_s)
      scope.where("COALESCE(orders.updated_at_external, orders.created_at) <= ?", to.end_of_day)
    end

    def apply_query(scope)
      return scope if filters[:q].blank?

      q = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q].to_s.strip)}%"

      scope.left_joins(:order_lines).where(
        <<~SQL.squish,
          orders.external_order_id ILIKE :q
          OR order_lines.external_sku ILIKE :q
          OR skus.code ILIKE :q
        SQL
        q: q
      ).references(:skus).distinct
    end

    def apply_status_guards(scope)
      status = filters[:status].present? ? normalize_status_filter(filters[:status]) : DEFAULT_STATUS

      case status
      when "AWAITING_FULFILLMENT"
        scope.where(
          <<~SQL.squish
            COALESCE(
              NULLIF(orders.raw_payload->>'tracking_number', ''),
              NULLIF(orders.raw_payload->>'tracking_no', '')
            ) IS NULL
            AND NOT EXISTS (
              SELECT 1
              FROM jsonb_array_elements(COALESCE(orders.raw_payload->'line_items', '[]'::jsonb)) AS li
              WHERE NULLIF(li->>'tracking_number', '') IS NOT NULL
                 OR NULLIF(li->>'tracking_no', '') IS NOT NULL
                 OR NULLIF(li->>'tracking_code', '') IS NOT NULL
            )
          SQL
        )
      when "READY_TO_SHIP"
        scope.where(
          <<~SQL.squish
            COALESCE(
              NULLIF(orders.raw_payload->>'tracking_number', ''),
              NULLIF(orders.raw_payload->>'tracking_no', '')
            ) IS NOT NULL
            OR EXISTS (
              SELECT 1
              FROM jsonb_array_elements(COALESCE(orders.raw_payload->'line_items', '[]'::jsonb)) AS li
              WHERE NULLIF(li->>'tracking_number', '') IS NOT NULL
                 OR NULLIF(li->>'tracking_no', '') IS NOT NULL
                 OR NULLIF(li->>'tracking_code', '') IS NOT NULL
            )
          SQL
        )
      else
        scope
      end
    end

    def normalize_shop_filter(value)
      Shop.normalize_filter_codes(value)
    end

    def normalize_status_filter(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      case raw.downcase
      when "pending"
        "PENDING"
      when "awaiting_fulfillment"
        "AWAITING_FULFILLMENT"
      when "ready_to_ship"
        "READY_TO_SHIP"
      when "awaiting_shipment"
        "AWAITING_FULFILLMENT"
      when "awaiting_collection"
        "READY_TO_SHIP"
      when "in_transit"
        "IN_TRANSIT"
      when "cancelled"
        "CANCELLED"
      when "delivered"
        "DELIVERED"
      when "completed"
        "COMPLETED"
      else
        raw.upcase
      end
    end
  end
end

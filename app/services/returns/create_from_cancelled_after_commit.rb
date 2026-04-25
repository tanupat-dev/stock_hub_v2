# frozen_string_literal: true

module Returns
  class CreateFromCancelledAfterCommit
    def self.call!(order:, previous_status:, current_status:, source:)
      new(order:, previous_status:, current_status:, source:).call!
    end

    def initialize(order:, previous_status:, current_status:, source:)
      @order = order
      @previous_status = previous_status.to_s
      @current_status = current_status.to_s
      @source = source.to_s
    end

    def call!
      return unless cancelled_after_commit?

      shipment = find_or_create_shipment!
      upsert_lines!(shipment)

      shipment.reload.refresh_status_store!

      Rails.logger.info(
        {
          event: "returns.create_from_cancelled_after_commit.done",
          order_id: @order.id,
          external_order_id: @order.external_order_id,
          return_shipment_id: shipment.id
        }.to_json
      )

      shipment
    end

    private

    def cancelled_after_commit?
      return false unless @current_status == "CANCELLED"
      return false unless @previous_status == "IN_TRANSIT"

      @order.order_lines.any? { |l| committed?(l) }
    end

    def committed?(line)
      InventoryAction.where(
        order_line_id: line.id,
        action_type: "commit"
      ).exists?
    end

    # ========================
    # Shipment (IDEMPOTENT)
    # ========================

    def find_or_create_shipment!
      existing = ReturnShipment
        .where(
          channel: @order.channel,
          shop_id: @order.shop_id,
          external_order_id: @order.external_order_id
        )
        .where("meta ->> 'source' = ?", "cancel_after_commit")
        .first

      return existing if existing.present?

      ReturnShipment.create!(
        channel: @order.channel,
        shop_id: @order.shop_id,
        order: @order,
        external_order_id: @order.external_order_id,
        status_store: "pending_scan",
        status_marketplace: "CANCELLED",
        tracking_number: extract_tracking_number,
        raw_payload: build_raw_payload,
        meta: {
          "source" => "cancel_after_commit",
          "previous_status" => @previous_status,
          "current_status" => @current_status
        }
      )
    end

    # ========================
    # Lines
    # ========================

    def upsert_lines!(shipment)
      now = Time.current

      existing_keys =
        shipment.return_shipment_lines
                .pluck(:order_line_id)
                .to_set

      rows = @order.order_lines.map do |line|
        next if existing_keys.include?(line.id)

        next unless committed?(line)

        sku = line.sku

        {
          return_shipment_id: shipment.id,
          order_line_id: line.id,
          sku_id: sku&.id,
          sku_code_snapshot: sku&.code.to_s,
          qty_returned: line.quantity,
          raw_payload: {},
          created_at: now,
          updated_at: now
        }
      end.compact

      return if rows.blank?

      ReturnShipmentLine.insert_all(rows)
    end

    # ========================
    # Helpers
    # ========================

    def extract_tracking_number
      @order.raw_payload["tracking_number"].to_s.presence
    end

    def build_raw_payload
      {
        "source" => "cancel_after_commit",
        "order_status" => {
          "previous" => @previous_status,
          "current" => @current_status
        }
      }
    end
  end
end

# frozen_string_literal: true

module Returns
  module Tiktok
    class CreateFromDeliveryFailed
      SOURCE = "tiktok_delivery_failed_rts"

      # Conservative RTS trigger:
      # - 41801 = cannot deliver / will return to seller
      # - 702xx = package is already in return-to-seller flow
      RTS_ACTION_CODES = [
        70201,
        70202,
        70203,
        70204,
        70206,
        70207
      ].freeze

      def self.call!(order:, tracking_data:)
        new(order:, tracking_data:).call!
      end

      def initialize(order:, tracking_data:)
        @order = order
        @tracking_data = tracking_data || {}
      end

      def call!
        return skip(:not_tiktok_order) unless @order&.channel.to_s == "tiktok"
        return skip(:not_in_transit) unless @order.status.to_s == "IN_TRANSIT"
        return skip(:missing_tracking_number) if tracking_number.blank?
        return skip(:no_committed_lines) if committed_lines.blank?
        return skip(:no_rts_tracking_event) if matched_event.blank?

        ReturnShipment.transaction do
          @order.lock!

          existing = existing_return_shipment
          return existing if existing.present?

          shipment = create_shipment!
          create_lines!(shipment)
          shipment.reload.refresh_status_store!

          Rails.logger.info(
            {
              event: "returns.tiktok.rts.detected",
              source: SOURCE,
              order_id: @order.id,
              external_order_id: @order.external_order_id,
              return_shipment_id: shipment.id,
              tracking_number: tracking_number,
              matched_action_code: matched_event["action_code"],
              matched_description: matched_event["description"],
              matched_update_time_millis: matched_event["update_time_millis"]
            }.to_json
          )

          shipment
        end
      rescue ActiveRecord::RecordNotUnique
        existing_return_shipment || raise
      end

      private

      def skip(reason)
        Rails.logger.info(
          {
            event: "returns.tiktok.rts.skip",
            reason: reason,
            order_id: @order&.id,
            external_order_id: @order&.external_order_id,
            tracking_number: tracking_number
          }.compact.to_json
        )

        nil
      end

      def tracking_number
        @tracking_number ||=
          @order.raw_payload&.dig("tracking_number").to_s.presence ||
          Array(@order.raw_payload&.dig("line_items")).first&.dig("tracking_number").to_s.presence
      end

      def tracking_events
        Array(@tracking_data["tracking"])
      end

      def matched_event
        @matched_event ||=
          tracking_events.find do |event|
            RTS_ACTION_CODES.include?(event["action_code"].to_i)
          end
      end

      def matched_event_time
        millis = matched_event&.dig("update_time_millis").to_i
        return nil if millis <= 0

        Time.at(millis / 1000.0)
      end

      def committed_lines
        @committed_lines ||=
          @order
            .order_lines
            .includes(:sku)
            .order(:id)
            .select { |line| committed_qty(line).positive? }
      end

      def committed_qty(line)
        InventoryAction
          .where(order_line_id: line.id, action_type: "commit")
          .sum(:quantity)
          .to_i
      end

      def existing_return_shipment
        ReturnShipment
          .where(order_id: @order.id)
          .first ||
          ReturnShipment
            .where(
              channel: @order.channel,
              shop_id: @order.shop_id,
              external_return_id: external_return_id
            )
            .first
      end

      def external_return_id
        "tiktok_rts:#{@order.external_order_id}"
      end

      def create_shipment!
        ReturnShipment.create!(
          channel: @order.channel,
          shop_id: @order.shop_id,
          order: @order,
          external_order_id: @order.external_order_id,
          external_return_id: external_return_id,
          tracking_number: tracking_number,
          status_marketplace: "delivery_failed_rts",
          status_store: "pending_scan",
          requested_at: matched_event_time || Time.current,
          return_carrier_method: shipping_provider,
          return_delivery_status: matched_event["action_code"].to_s,
          raw_payload: {
            "source" => SOURCE,
            "tracking_number" => tracking_number,
            "matched_event" => matched_event,
            "tracking" => tracking_events,
            "order_status" => @order.status
          },
          meta: {
            "source" => SOURCE,
            "trigger" => "tiktok_fulfillment_tracking",
            "matched_action_code" => matched_event["action_code"],
            "matched_description" => matched_event["description"],
            "matched_update_time_millis" => matched_event["update_time_millis"],
            "tracking_number" => tracking_number
          },
          last_seen_at_external: Time.current
        )
      end

      def create_lines!(shipment)
        now = Time.current

        existing_order_line_ids =
          shipment
            .return_shipment_lines
            .pluck(:order_line_id)
            .compact
            .to_set

        rows = committed_lines.map do |line|
          next if existing_order_line_ids.include?(line.id)

          sku = line.sku

          {
            return_shipment_id: shipment.id,
            order_line_id: line.id,
            sku_id: sku&.id,
            external_line_id: line.external_line_id.to_s.presence,
            sku_code_snapshot: sku&.code.to_s.presence || line.external_sku.to_s,
            qty_returned: line.quantity.to_i.positive? ? line.quantity.to_i : 1,
            raw_payload: {
              "source" => SOURCE,
              "order_line_id" => line.id,
              "external_line_id" => line.external_line_id,
              "external_sku" => line.external_sku,
              "committed_qty" => committed_qty(line)
            },
            created_at: now,
            updated_at: now
          }
        end.compact

        return if rows.blank?

        with_external_line_id = rows.select { |row| row[:external_line_id].present? }
        without_external_line_id = rows.select { |row| row[:external_line_id].blank? }

        if with_external_line_id.any?
          ReturnShipmentLine.upsert_all(
            with_external_line_id,
            unique_by: :uniq_return_shipment_lines_external_line,
            record_timestamps: false,
            update_only: %i[
              order_line_id
              sku_id
              sku_code_snapshot
              qty_returned
              raw_payload
              updated_at
            ]
          )
        end

        without_external_line_id.each do |attrs|
          shipment.return_shipment_lines.create!(attrs.except(:return_shipment_id))
        end
      end

      def shipping_provider
        @order.raw_payload&.dig("shipping_provider").to_s.presence ||
          Array(@order.raw_payload&.dig("line_items")).first&.dig("shipping_provider_name").to_s.presence
      end
    end
  end
end

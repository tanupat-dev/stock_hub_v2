# frozen_string_literal: true

module Orders
  module StatusUpdateGuard
    module_function

    def skip_reason(
      previous_status:,
      incoming_status:,
      previous_update_time: nil,
      incoming_update_time: nil,
      compare_update_time: false
    )
      if compare_update_time &&
          stale_marketplace_update?(
            previous_update_time: previous_update_time,
            incoming_update_time: incoming_update_time
          )
        return "stale_marketplace_update"
      end

      return "terminal_status_downgrade" if terminal_status_downgrade?(
        previous_status: previous_status,
        incoming_status: incoming_status
      )

      nil
    end

    def stale_marketplace_update?(previous_update_time:, incoming_update_time:)
      previous = previous_update_time.to_i
      incoming = incoming_update_time.to_i

      previous.positive? && incoming.positive? && incoming < previous
    end

    # We use central status only.
    #
    # Block examples:
    # - DELIVERED -> AWAITING_FULFILLMENT
    # - COMPLETED -> READY_TO_SHIP
    # - DELIVERED -> IN_TRANSIT
    # - COMPLETED -> UNPAID
    #
    # Do NOT block DELIVERED/COMPLETED -> CANCELLED here yet.
    # That can be refund/return/cancel-after-delivery behavior and needs separate audit.
    def terminal_status_downgrade?(previous_status:, incoming_status:)
      previous = previous_status.to_s
      incoming = incoming_status.to_s

      return false unless Orders::StatusTransitionGuard.terminal_commit_status?(previous)

      Orders::StatusTransitionGuard.reservable_status?(incoming) ||
        Orders::StatusTransitionGuard.committable_status?(incoming) ||
        incoming == "UNPAID"
    end

    def log_skip!(
      channel:,
      shop_id:,
      external_order_id:,
      previous_status:,
      incoming_status:,
      previous_update_time: nil,
      incoming_update_time: nil,
      reason:
    )
      Rails.logger.warn(
        {
          event: "orders.upsert.status_update_skipped",
          reason: reason,
          channel: channel,
          shop_id: shop_id,
          external_order_id: external_order_id,
          previous_status: previous_status,
          incoming_status: incoming_status,
          previous_update_time: previous_update_time,
          incoming_update_time: incoming_update_time
        }.to_json
      )
    end
  end
end

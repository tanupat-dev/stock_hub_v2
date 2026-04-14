# frozen_string_literal: true

module Orders
  module Tiktok
    class ApplyPolicy
      def self.call!(order:, raw_order:, previous_status:)
        new(order, raw_order, previous_status).call!
      end

      def initialize(order, raw_order, previous_status)
        @order = order
        @raw = raw_order
        @previous_status = previous_status.to_s.presence
      end

      def call!
        status = @raw["status"].to_s

        action =
          if Orders::StatusTransitionGuard.should_reserve?(
               previous_status: @previous_status,
               current_status: status
             )
            :reserve
          elsif Orders::StatusTransitionGuard.should_commit?(
                  previous_status: @previous_status,
                  current_status: status
                )
            :commit
          elsif Orders::StatusTransitionGuard.should_release?(
                  previous_status: @previous_status,
                  current_status: status
                )
            :release
          else
            nil
          end

        return noop_payload(status) if action.nil?

        Orders::ApplyInventoryPolicy.call!(
          order: @order,
          action: action,
          idempotency_prefix: "tiktok:order:#{@order.external_order_id}",
          meta: {
            source: "tiktok_poll",
            status: status,
            previous_status: @previous_status,
            update_time: @raw["update_time"]
          }
        )
      end

      private

      def noop_payload(status)
        {
          ok: true,
          action: nil,
          reason: noop_reason(status),
          status: status,
          previous_status: @previous_status
        }
      end

      def noop_reason(status)
        if Orders::StatusTransitionGuard.noop_status?(status)
          "noop_terminal_status"
        elsif status == "IN_TRANSIT" && @previous_status.blank?
          "first_seen_in_transit_no_commit"
        elsif status == "CANCELLED" && @previous_status.blank?
          "first_seen_cancelled_no_release"
        elsif Orders::StatusTransitionGuard.reservable_status?(status) && @previous_status == status
          "same_status_noop"
        else
          "noop_status"
        end
      end
    end
  end
end

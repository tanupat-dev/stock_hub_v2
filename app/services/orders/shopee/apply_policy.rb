# frozen_string_literal: true

module Orders
  module Shopee
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
        status = @raw.fetch("status").to_s

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

        apply!(action)
      end

      private

      def apply!(action)
        prefix = Orders::Shopee::Idempotency.policy_prefix(@order.external_order_id)
        Orders::Shopee::Idempotency.validate_policy_prefix!(prefix)

        Orders::ApplyInventoryPolicy.call!(
          order: @order,
          action: action,
          idempotency_prefix: prefix,
          meta: {
            source: "shopee_import",
            status: @raw["status"],
            previous_status: @previous_status,
            ordered_at: @raw["ordered_at"],
            tracking_number: @raw["tracking_number"]
          }
        )
      end

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
          "unknown_or_noop_status"
        end
      end
    end
  end
end

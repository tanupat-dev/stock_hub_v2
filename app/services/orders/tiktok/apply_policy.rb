# frozen_string_literal: true

module Orders
  module Tiktok
    class ApplyPolicy
      SOURCE = "tiktok_poll"

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

        action = transition_action(status)
        action ||= fallback_action(status)

        if action.nil?
          Returns::CreateFromCancelledAfterCommit.call!(
            order: @order,
            previous_status: @previous_status,
            current_status: status,
            source: "tiktok"
          )

          return noop_payload(status)
        end

        if action == :commit && fallback_commit?(status) && !Orders::OpenReserve.commit_safe?(@order)
          log_repair_required(status)

          return {
            ok: true,
            action: nil,
            reason: "commit_would_make_on_hand_negative_repair_required",
            status: status,
            previous_status: @previous_status,
            open_reserve: Orders::OpenReserve.summary(@order)
          }
        end

        result = apply!(action, status)

        if action == :commit && status == "CANCELLED"
          Returns::CreateFromCancelledAfterCommit.call!(
            order: @order,
            previous_status: @previous_status,
            current_status: status,
            source: "tiktok"
          )
        end

        result
      end

      private

      def transition_action(status)
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
        end
      end

      def fallback_action(status)
        return nil unless Orders::OpenReserve.exists?(@order)

        Orders::StatusTransitionGuard.fallback_action_for_open_reserve(
          previous_status: @previous_status,
          current_status: status
        )
      end

      def fallback_commit?(status)
        Orders::OpenReserve.exists?(@order) &&
          Orders::StatusTransitionGuard.fallback_action_for_open_reserve(
            previous_status: @previous_status,
            current_status: status
          ) == :commit
      end

      def apply!(action, status)
        Orders::ApplyInventoryPolicy.call!(
          order: @order,
          action: action,
          idempotency_prefix: "tiktok:order:#{@order.external_order_id}",
          meta: {
            source: SOURCE,
            status: status,
            previous_status: @previous_status,
            update_time: @raw["update_time"]
          }
        )
      end

      def log_repair_required(status)
        Rails.logger.warn(
          {
            event: "orders.apply_policy.repair_required",
            reason: "commit_would_make_on_hand_negative",
            channel: @order.channel,
            shop_id: @order.shop_id,
            order_id: @order.id,
            external_order_id: @order.external_order_id,
            previous_status: @previous_status,
            current_status: status,
            open_reserve: Orders::OpenReserve.summary(@order)
          }.to_json
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
          "noop_status"
        end
      end
    end
  end
end

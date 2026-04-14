# frozen_string_literal: true

module Returns
  module Tiktok
    class StatusMapper
      COMPLETED_STATUSES = %w[
        REFUND_SUCCESS
        REFUND_COMPLETED
        RETURN_COMPLETED
        RETURN_OR_REFUND_REQUEST_COMPLETE
        CLOSED
        FINISHED
        COMPLETE
        COMPLETED
      ].freeze

      SHIPPED_BACK_STATUSES = %w[
        BUYER_SHIPPED
        BUYER_SHIPPED_RETURN
        RETURN_IN_TRANSIT
        RETURN_DELIVERED
        RETURN_RECEIVED
        SELLER_RECEIVED_RETURN
        SELLER_CONFIRM_RECEIVE
        WAREHOUSE_RECEIVED_RETURN
      ].freeze

      REQUESTED_STATUSES = %w[
        ORDER_RETURN
        ORDER_REFUND
        RETURN_OR_REFUND_REQUEST_PENDING
        RETURN_OR_REFUND_REQUEST_APPROVED
        RETURN_OR_REFUND_REQUEST_CANCEL
      ].freeze

      def self.call(return_status:)
        status = normalize(return_status)

        return "completed" if completed?(status)
        return "shipped_back" if shipped_back?(status)
        return "requested" if requested?(status)
        return "requested" if status.present?

        "requested"
      end

      def self.normalize(value)
        value.to_s.strip.upcase.presence
      end

      def self.completed?(status)
        COMPLETED_STATUSES.include?(status)
      end

      def self.shipped_back?(status)
        SHIPPED_BACK_STATUSES.include?(status)
      end

      def self.requested?(status)
        REQUESTED_STATUSES.include?(status)
      end
    end
  end
end

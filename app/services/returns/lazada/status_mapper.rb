# frozen_string_literal: true

module Returns
  module Lazada
    class StatusMapper
      def self.call(reverse_status:, ofc_status: nil, request_type: nil)
        reverse = normalize(reverse_status)
        ofc = normalize(ofc_status)
        req = normalize(request_type)

        return "completed" if completed?(reverse, ofc, req)
        return "shipped_back" if shipped_back?(reverse, ofc, req)
        return "requested" if reverse.present? || ofc.present? || req.present?

        "requested"
      end

      def self.normalize(value)
        value.to_s.strip.upcase.presence
      end

      def self.completed?(reverse, ofc, _req)
        %w[
          REFUND_SUCCESS
          REFUND_COMPLETE
          RETURN_COMPLETE
          COMPLETE
          COMPLETED
          CLOSED
          FINISH
          FINISHED
        ].include?(reverse) ||
          %w[
            RETURN_DELIVERED
            BUYER_RECEIVED
            RECEIVED
            QC_PASSED
            REFUND_SUCCESS
            COMPLETE
            COMPLETED
            FINISHED
          ].include?(ofc)
      end

      def self.shipped_back?(reverse, ofc, _req)
        %w[
          REQUEST_PROCESSING
          RETURN_SHIPPING
          SHIPPED_BACK
          RETURNED
          IN_TRANSIT
        ].include?(reverse) ||
          %w[
            PICKED_UP
            INBOUND
            RECEIVED_AT_WAREHOUSE
            RETURN_TO_SELLER
            RETURNED_TO_SELLER
          ].include?(ofc)
      end
    end
  end
end

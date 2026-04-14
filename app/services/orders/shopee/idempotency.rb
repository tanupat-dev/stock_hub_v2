# frozen_string_literal: true

module Orders
  module Shopee
    module Idempotency
      module_function

      PREFIX_NAMESPACE = "shopee".freeze
      PREFIX_RESOURCE  = "order".freeze

      def policy_prefix(external_order_id)
        order_id = normalize_external_order_id(external_order_id)
        "#{PREFIX_NAMESPACE}:#{PREFIX_RESOURCE}:#{order_id}"
      end

      def normalize_external_order_id(value)
        raw = value.to_s.strip
        raise ArgumentError, "external_order_id is required" if raw.blank?

        raw
      end

      def validate_policy_prefix!(value)
        prefix = value.to_s

        unless prefix.start_with?("#{PREFIX_NAMESPACE}:#{PREFIX_RESOURCE}:")
          raise ArgumentError, "invalid shopee idempotency prefix: #{prefix}"
        end

        if prefix.include?("shoopee") || prefix.include?("orrder")
          raise ArgumentError, "suspicious shopee idempotency prefix: #{prefix}"
        end

        true
      end
    end
  end
end

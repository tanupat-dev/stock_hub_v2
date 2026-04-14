# frozen_string_literal: true

module Orders
  module StatusTracking
    module_function

    def present?(value)
      normalized(value).present?
    end

    def normalized(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      lowered = raw.downcase

      return nil if %w[- -- n/a na none null nil].include?(lowered)

      raw
    end

    def any_in_order_payload?(raw_order)
      payload = raw_order || {}

      top_level = [
        payload["tracking_number"],
        payload["tracking_no"]
      ]

      line_level = Array(payload["line_items"]).flat_map do |li|
        [
          li["tracking_number"],
          li["tracking_no"],
          li["tracking_code"]
        ]
      end

      (top_level + line_level).any? { |v| present?(v) }
    end
  end
end

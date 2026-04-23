# frozen_string_literal: true

module Orders
  module StatusTransitionGuard
    module_function

    RESERVABLE_STATUSES = %w[
      ON_HOLD
      AWAITING_FULFILLMENT
      READY_TO_SHIP
      PARTIALLY_SHIPPING
      AWAITING_SHIPMENT
      AWAITING_COLLECTION
    ].freeze

    COMMITTABLE_STATUSES = %w[
      IN_TRANSIT
    ].freeze

    NOOP_STATUSES = %w[
      DELIVERED
      COMPLETED
      UNPAID
    ].freeze

    RELEASE_STATUSES = %w[
      CANCELLED
    ].freeze

    def reservable_status?(status)
      RESERVABLE_STATUSES.include?(status.to_s)
    end

    def committable_status?(status)
      COMMITTABLE_STATUSES.include?(status.to_s)
    end

    def noop_status?(status)
      NOOP_STATUSES.include?(status.to_s)
    end

    def releasable_status?(status)
      RELEASE_STATUSES.include?(status.to_s)
    end

    # Policy:
    # - first seen + reservable => reserve
    # - repeated same reservable status => no-op at caller level
    # - reservable -> another reservable => allow reserve (idempotent)
    def should_reserve?(previous_status:, current_status:)
      return false unless reservable_status?(current_status)

      previous = previous_status.to_s.presence
      return true if previous.blank?
      return false if previous == current_status.to_s

      true
    end

    # Policy:
    # - first seen + IN_TRANSIT => do NOT commit
    # - commit only when transitioning from reservable -> IN_TRANSIT
    def should_commit?(previous_status:, current_status:)
      return false unless current_status.to_s == "IN_TRANSIT"

      previous = previous_status.to_s.presence
      return false if previous.blank?

      reservable_status?(previous)
    end

    # Policy:
    # - first seen + CANCELLED => do NOT release
    # - release only when transitioning from reservable -> CANCELLED
    def should_release?(previous_status:, current_status:)
      return false unless current_status.to_s == "CANCELLED"

      previous = previous_status.to_s.presence
      return false if previous.blank?

      reservable_status?(previous)
    end
  end
end

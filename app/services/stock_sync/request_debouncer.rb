# frozen_string_literal: true

module StockSync
  class RequestDebouncer
    DEFAULT_DEBOUNCE_SECONDS = 5

    def self.call!(sku:, reason:, debounce_seconds: DEFAULT_DEBOUNCE_SECONDS)
      new(sku:, reason:, debounce_seconds:).call!
    end

    def initialize(sku:, reason:, debounce_seconds:)
      @sku = sku
      @reason = reason.to_s.presence || "inventory_changed"
      @debounce_seconds = debounce_seconds.to_i > 0 ? debounce_seconds.to_i : DEFAULT_DEBOUNCE_SECONDS
    end

    def call!
      raise ArgumentError, "sku is required" if @sku.nil?

      now = Time.current
      scheduled_for = now + @debounce_seconds.seconds

      req = nil
      should_enqueue = false

      StockSyncRequest.transaction do
        req = StockSyncRequest.lock.find_by(sku_id: @sku.id)

        if req.nil?
          req = StockSyncRequest.create!(
            sku_id: @sku.id,
            status: "pending",
            last_reason: @reason,
            first_requested_at: now,
            last_requested_at: now,
            scheduled_for: scheduled_for,
            last_enqueued_at: nil,
            last_processed_at: nil,
            last_error: nil
          )
          should_enqueue = true
        else
          should_enqueue = req.last_enqueued_at.blank?

          req.update!(
            status: "pending",
            last_reason: @reason,
            last_requested_at: now,
            scheduled_for: [ req.scheduled_for, scheduled_for ].max,
            last_error: nil
          )
        end
      end

      if should_enqueue
        DebouncedSyncStockJob
          .set(wait_until: req.scheduled_for)
          .perform_later(@sku.id)

        req.update_column(:last_enqueued_at, Time.current)
      end

      Rails.logger.info(
        {
          event: "stock_sync.request_debouncer",
          sku_id: @sku.id,
          sku: @sku.code,
          reason: @reason,
          debounce_seconds: @debounce_seconds,
          scheduled_for: req.scheduled_for,
          status: req.status,
          enqueued_job: should_enqueue
        }.to_json
      )

      req
    end
  end
end

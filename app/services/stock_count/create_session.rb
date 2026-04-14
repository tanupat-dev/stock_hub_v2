# frozen_string_literal: true

module StockCount
  class CreateSession
    def self.call!(shop:, idempotency_key:, meta: {})
      new(shop:, idempotency_key:, meta:).call!
    end

    def initialize(shop:, idempotency_key:, meta:)
      @shop = shop
      @idempotency_key = idempotency_key
      @meta = meta || {}
    end

    def call!
      raise ArgumentError, "shop is required" if @shop.nil?

      StockCountSession.transaction do
        existing = StockCountSession.find_by(idempotency_key: @idempotency_key)
        return existing if existing

        session = StockCountSession.create!(
          shop: @shop,
          session_number: generate_session_number,
          status: "open",
          idempotency_key: @idempotency_key,
          meta: @meta
        )

        Rails.logger.info(
          {
            event: "stock_count.create_session",
            stock_count_session_id: session.id,
            session_number: session.session_number,
            shop_id: @shop.id,
            idempotency_key: @idempotency_key
          }.to_json
        )

        session
      end
    end

    private

    def generate_session_number
      "SC-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
    end
  end
end

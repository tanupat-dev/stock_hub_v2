# frozen_string_literal: true

module Orders
  module Tiktok
    class Poll
      # กัน order update "มาช้า" / data refresh lag
      SAFETY_LAG_SECONDS = 90

      # กัน loop หน้ายาวผิดปกติ
      MAX_PAGES = 500

      def self.call!(shop:)
        new(shop).call!
      end

      def initialize(shop)
        @shop = shop
        raise ArgumentError, "shop required" if @shop.nil?
        raise ArgumentError, "shop is not tiktok" unless @shop.channel == "tiktok"
      end

      def call!
        now_ts = Time.now.to_i
        window_lt = now_ts - SAFETY_LAG_SECONDS

        # cursor: last_seen_update_time (seconds unix)
        window_ge = (@shop.last_seen_update_time.presence || 0).to_i

        log_info(
          event: "tiktok.poll.start",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          window_ge: window_ge,
          window_lt: window_lt
        )

        next_token = nil
        pages = 0
        max_update_time_seen = window_ge
        processed = 0

        loop do
          pages += 1
          raise "poll exceeded max pages (#{MAX_PAGES})" if pages > MAX_PAGES

          resp = Orders::Tiktok::SearchOrders.call!(
            shop: @shop,
            update_time_ge: window_ge,
            update_time_lt: window_lt,
            page_token: next_token
          )

          rows = resp[:orders]
          processed += rows.size

          rows.each do |raw|
            ut = raw["update_time"].to_i
            max_update_time_seen = ut if ut > max_update_time_seen

            Orders::Tiktok::Upsert.call!(
              shop: @shop,
              raw_order: raw
            )
          end

          next_token = resp[:next_page_token]
          break if next_token.blank?
        end

        # IMPORTANT: advance cursor to max_update_time_seen (not window_lt)
        @shop.update_columns(
          last_seen_update_time: max_update_time_seen,
          last_polled_at: Time.current,
          updated_at: Time.current
        )

        log_info(
          event: "tiktok.poll.done",
          shop_id: @shop.id,
          shop_code: @shop.shop_code,
          window_ge: window_ge,
          window_lt: window_lt,
          pages: pages,
          processed: processed,
          max_update_time_seen: max_update_time_seen
        )

        {
          ok: true,
          shop_id: @shop.id,
          pages: pages,
          processed: processed,
          max_update_time_seen: max_update_time_seen
        }
      rescue => e
        log_error(
          event: "tiktok.poll.fail",
          shop_id: @shop&.id,
          shop_code: @shop&.shop_code,
          err_class: e.class.name,
          err_message: e.message
        )
        raise
      end

      private

      def log_info(payload)
        Rails.logger.info(payload.to_json)
      end

      def log_error(payload)
        Rails.logger.error(payload.to_json)
      end
    end
  end
end
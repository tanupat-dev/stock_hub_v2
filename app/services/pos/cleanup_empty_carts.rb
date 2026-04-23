# frozen_string_literal: true

module Pos
  class CleanupEmptyCarts
    DEFAULT_OLDER_THAN_MINUTES = 30

    def self.call!(older_than_minutes: DEFAULT_OLDER_THAN_MINUTES, limit: 200)
      new(older_than_minutes:, limit:).call!
    end

    def initialize(older_than_minutes:, limit:)
      @older_than_minutes = older_than_minutes.to_i
      @limit = limit.to_i
      @limit = 200 if @limit <= 0
    end

    def call!
      cutoff = @older_than_minutes.minutes.ago
      cleaned_ids = []

      scope
        .limit(@limit)
        .find_each do |sale|
          PosSale.transaction do
            sale.lock!
            sale.reload

            next unless eligible?(sale)

            now = Time.current

            sale.pos_sale_lines.active_lines.update_all(
              status: "voided",
              updated_at: now
            )

            sale.update!(
              status: "voided",
              voided_at: now,
              item_count: 0,
              meta: sale.meta.to_h.merge(
                "void_reason" => "auto_cleanup_empty_cart",
                "cleanup_meta" => {
                  "source" => "cleanup_empty_pos_carts_job",
                  "older_than_minutes" => @older_than_minutes
                }
              )
            )

            cleaned_ids << sale.id

            Rails.logger.info(
              {
                event: "pos.cleanup_empty_cart.success",
                sale_id: sale.id,
                sale_number: sale.sale_number,
                older_than_minutes: @older_than_minutes
              }.to_json
            )
          end
        rescue => e
          Rails.logger.error(
            {
              event: "pos.cleanup_empty_cart.error",
              sale_id: sale&.id,
              sale_number: sale&.sale_number,
              err_class: e.class.name,
              err_message: e.message
            }.to_json
          )
        end

      {
        ok: true,
        cleaned_count: cleaned_ids.size,
        cleaned_ids: cleaned_ids
      }
    end

    private

    def scope
      PosSale
        .where(status: "cart", item_count: 0)
        .where("created_at <= ?", @older_than_minutes.minutes.ago)
        .order(created_at: :asc, id: :asc)
    end

    def eligible?(sale)
      return false unless sale.cart?
      return false unless sale.item_count.to_i.zero?
      return false if sale.created_at > @older_than_minutes.minutes.ago

      sale.pos_sale_lines.active_lines.none?
    end
  end
end

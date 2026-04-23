# frozen_string_literal: true

class CleanupEmptyPosCartsJob < ApplicationJob
  queue_as :default

  def perform(older_than_minutes: 30, limit: 200)
    result = Pos::CleanupEmptyCarts.call!(
      older_than_minutes: older_than_minutes,
      limit: limit
    )

    Rails.logger.info(
      {
        event: "pos.cleanup_empty_carts.done",
        older_than_minutes: older_than_minutes,
        limit: limit,
        cleaned_count: result[:cleaned_count],
        cleaned_ids: result[:cleaned_ids]
      }.to_json
    )

    result
  end
end

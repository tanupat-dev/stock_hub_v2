# frozen_string_literal: true

class InventoryReconcileRun < ApplicationRecord
  belongs_to :shop

  validates :ran_at, presence: true
  validates :mismatched_count, :unmapped_count, :pushed_count,
            numericality: { greater_than_or_equal_to: 0 }
end

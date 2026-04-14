# frozen_string_literal: true

class CreateSolidQueueTables < ActiveRecord::Migration[8.0]
  def change
    # โหลด schema ของ SolidQueue เข้า DB หลัก (primary)
    load Rails.root.join("db", "queue_schema.rb")
  end
end
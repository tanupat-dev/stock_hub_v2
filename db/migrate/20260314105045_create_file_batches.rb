# frozen_string_literal: true

class CreateFileBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :file_batches do |t|
      t.string  :channel, null: false
      t.bigint  :shop_id, null: false
      t.string  :kind, null: false
      t.string  :status, null: false, default: "pending"

      t.string  :source_filename

      t.integer :total_rows, null: false, default: 0
      t.integer :success_rows, null: false, default: 0
      t.integer :failed_rows, null: false, default: 0

      t.jsonb   :meta, null: false, default: {}

      t.text    :error_summary

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_foreign_key :file_batches, :shops

    add_index :file_batches, [ :channel, :shop_id, :kind ]
    add_index :file_batches, :status
    add_index :file_batches, :created_at
  end
end

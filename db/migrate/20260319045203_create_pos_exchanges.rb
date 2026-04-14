# frozen_string_literal: true

class CreatePosExchanges < ActiveRecord::Migration[8.0]
  def change
    create_table :pos_exchanges do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :pos_sale, null: false, foreign_key: true
      t.references :pos_return, foreign_key: true
      t.references :new_pos_sale, foreign_key: { to_table: :pos_sales }

      t.string :exchange_number, null: false
      t.string :status, null: false, default: "open"
      t.string :idempotency_key, null: false

      t.datetime :completed_at
      t.datetime :cancelled_at

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :pos_exchanges, :exchange_number, unique: true
    add_index :pos_exchanges, :status
    add_index :pos_exchanges, :idempotency_key, unique: true
    add_index :pos_exchanges, [ :shop_id, :created_at ]
    add_index :pos_exchanges, [ :pos_sale_id, :created_at ]
  end
end

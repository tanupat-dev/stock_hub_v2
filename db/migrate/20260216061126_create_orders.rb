class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :channel, null: false
      t.references :shop, null: false, foreign_key: true

      t.string :external_order_id, null: false
      t.string :status, null: false

      # ตามที่มึงต้องการ
      t.string :buyer_name
      t.string :province
      t.text :buyer_note

      # polling pointer + sorting
      t.bigint :updated_time_external
      t.datetime :updated_at_external

      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps
    end

    add_index :orders, [:channel, :shop_id, :external_order_id],
              unique: true, name: "uniq_orders_channel_shop_external"

    add_index :orders, [:shop_id, :updated_time_external]
    add_index :orders, [:channel, :status]
  end
end
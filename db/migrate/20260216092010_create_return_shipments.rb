class CreateReturnShipments < ActiveRecord::Migration[8.0]
  def change
    create_table :return_shipments do |t|
      t.string  :channel, null: false
      t.bigint  :shop_id, null: false
      t.bigint  :order_id, null: false

      # ตัวไหนก็ได้ที่ polling ให้มา (อย่างน้อยต้องมีสักตัว)
      t.string  :external_return_id         # เช่น reverse_order_id / return_id
      t.string  :tracking_number            # เลข tracking ขนส่ง
      t.string  :external_order_id, null: false

      # สถานะฝั่ง marketplace (เก็บไว้) + สถานะฝั่งร้านเรา (สำคัญ)
      t.string  :status_marketplace
      t.string  :status_store, null: false, default: "pending_scan" # pending_scan / received_scanned

      t.datetime :last_seen_at_external
      t.jsonb   :meta, null: false, default: {}

      t.timestamps
    end

    add_foreign_key :return_shipments, :shops
    add_foreign_key :return_shipments, :orders

    # ค้นหาเร็วตามที่ POS จะกรอก
    add_index :return_shipments, %i[channel shop_id external_order_id], name: "idx_return_shipments_order_lookup"
    add_index :return_shipments, :tracking_number
    add_index :return_shipments, :external_return_id

    # กันซ้ำแบบ practical:
    # - ถ้ามี external_return_id ให้ unique ตาม shop/channel
    add_index :return_shipments, %i[channel shop_id external_return_id],
              unique: true,
              where: "external_return_id IS NOT NULL",
              name: "uniq_return_shipments_by_external_return"

    # - ถ้ามี tracking_number ให้ unique (ในความจริงควร unique)
    add_index :return_shipments, :tracking_number,
              unique: true,
              where: "tracking_number IS NOT NULL",
              name: "uniq_return_shipments_by_tracking"
  end
end
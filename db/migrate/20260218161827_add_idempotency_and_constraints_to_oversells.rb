# frozen_string_literal: true

class AddIdempotencyAndConstraintsToOversells < ActiveRecord::Migration[8.0]
  def change
    # ---- oversell_incidents ----
    add_column :oversell_incidents, :idempotency_key, :string, null: false, default: ""

    # backfill safety (เผื่อมีแถวเก่าใน dev)
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE oversell_incidents
          SET idempotency_key = 'backfill:' || id::text
          WHERE idempotency_key = '';
        SQL
      end
    end

    add_index :oversell_incidents, :idempotency_key, unique: true
    add_check_constraint :oversell_incidents, "shortfall_qty > 0", name: "chk_oversell_incident_shortfall_positive"

    # ---- oversell_allocations ----
    add_index :oversell_allocations,
              [:oversell_incident_id, :order_line_id],
              unique: true,
              name: "uniq_oversell_alloc_incident_line"
  end
end
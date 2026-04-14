class RelaxInventoryAvailableConstraint < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      ALTER TABLE inventory_balances
      DROP CONSTRAINT IF EXISTS chk_available_non_negative;
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      DROP CONSTRAINT IF EXISTS chk_on_hand_non_negative;
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      DROP CONSTRAINT IF EXISTS chk_reserved_non_negative;
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      ADD CONSTRAINT chk_on_hand_non_negative CHECK (on_hand >= 0);
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      ADD CONSTRAINT chk_reserved_non_negative CHECK (reserved >= 0);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE inventory_balances
      DROP CONSTRAINT IF EXISTS chk_on_hand_non_negative;
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      DROP CONSTRAINT IF EXISTS chk_reserved_non_negative;
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      ADD CONSTRAINT chk_on_hand_non_negative CHECK (on_hand >= 0);
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      ADD CONSTRAINT chk_reserved_non_negative CHECK (reserved >= 0);
    SQL

    execute <<~SQL
      ALTER TABLE inventory_balances
      ADD CONSTRAINT chk_available_non_negative CHECK ((on_hand - reserved) >= 0);
    SQL
  end
end

# frozen_string_literal: true

class ChangeStatsDistanceToBigint < ActiveRecord::Migration[8.0]
  def up
    change_column :stats, :distance, :bigint, null: false
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Cannot safely narrow stats.distance back to integer: rows persisted ' \
          'after this migration may exceed the int4 range and would raise or truncate.'
  end
end

# frozen_string_literal: true

class ChangeTripsDistanceToBigint < ActiveRecord::Migration[8.1]
  def up
    change_column :trips, :distance, :bigint
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Cannot safely narrow trips.distance back to integer after bigint values have been persisted.'
  end
end

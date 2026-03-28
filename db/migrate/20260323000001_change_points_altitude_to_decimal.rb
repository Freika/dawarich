# frozen_string_literal: true

# Stage 1 of altitude type migration (integer → decimal).
# Adding the new column is instant (no table rewrite, no lock).
# Stage 2 (next release): backfill altitude_decimal from altitude, swap columns.
class ChangePointsAltitudeToDecimal < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:points, :altitude_decimal)

    add_column :points, :altitude_decimal, :decimal, precision: 10, scale: 2
  end

  def down
    remove_column :points, :altitude_decimal if column_exists?(:points, :altitude_decimal)
  end
end

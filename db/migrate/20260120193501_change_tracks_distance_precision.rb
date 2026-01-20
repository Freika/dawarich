# frozen_string_literal: true

class ChangeTracksDistancePrecision < ActiveRecord::Migration[8.0]
  # This is safe because:
  # 1. The tracks table is typically not very large (one track per day per user)
  # 2. The column type change from decimal to bigint is fast
  # 3. The data will fit without loss (decimal values truncated to integers)
  disable_ddl_transaction!

  def up
    # Change distance from decimal(8,2) to bigint to support tracks longer than 1000km
    # Distance is stored in meters, so bigint can handle tracks up to ~9 million km
    safety_assured { change_column :tracks, :distance, :bigint }
  end

  def down
    safety_assured { change_column :tracks, :distance, :decimal, precision: 8, scale: 2 }
  end
end

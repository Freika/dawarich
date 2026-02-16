# frozen_string_literal: true

class OptimizePointsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Add motion_data column for transportation-relevant fields.
    # Replaces storing full raw_data for non-Google sources.
    add_column :points, :motion_data, :jsonb, default: {}, null: false unless column_exists?(:points, :motion_data)

    # idx_points_user_city: 304 MB, 0 scans — never used
    remove_index :points, name: :idx_points_user_city, if_exists: true

    # Replace full reverse_geocoded_at index (1,149 MB, 2,334 scans) with a
    # partial index covering only NULL rows (~500k rows vs 34M).
    # The nightly geocoding job queries WHERE reverse_geocoded_at IS NULL,
    # so this partial index serves the same purpose at a fraction of the size.
    add_index :points, :id,
              name: :index_points_on_not_reverse_geocoded,
              where: 'reverse_geocoded_at IS NULL',
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :points, name: :index_points_on_reverse_geocoded_at, if_exists: true
  end

  def down
    remove_column :points, :motion_data, if_exists: true

    add_index :points, :reverse_geocoded_at,
              name: :index_points_on_reverse_geocoded_at,
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :points, name: :index_points_on_not_reverse_geocoded, if_exists: true

    add_index :points, %i[user_id city],
              name: :idx_points_user_city,
              algorithm: :concurrently,
              if_not_exists: true
  end
end

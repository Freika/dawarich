# frozen_string_literal: true

class DropUnusedPointsIndexes < ActiveRecord::Migration[8.0]
  def change
    # country_id: No queries filter by country_id (only SET on write).
    # The one-time data migration job (SetPointsCountryIdsJob) is already completed.
    remove_index :points, column: :country_id,
                          name: 'index_points_on_country_id',
                          if_exists: true

    # archived_uncleared: Partial index for (raw_data_archived = true AND raw_data != '{}').
    # Added in 20260320000002 for the clearing job, but clearing is complete
    # and the condition matches near-zero rows after geodata/raw_data cleanup.
    remove_index :points, name: 'index_points_on_archived_uncleared',
                          if_exists: true

    # archived_true: Partial index on raw_data_archived WHERE true.
    # Archival scopes add additional conditions that don't benefit from this partial.
    # Only 1 scan recorded across months of autobase usage.
    remove_index :points, name: 'index_points_on_archived_true',
                          if_exists: true
  end
end

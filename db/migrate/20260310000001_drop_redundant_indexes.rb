# frozen_string_literal: true

class DropRedundantIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # index_points_on_user_id (629 MB) is redundant:
    # Leading column covered by index_points_on_user_id_and_timestamp,
    # idx_points_track_generation, idx_points_user_visit_null_timestamp,
    # and idx_points_user_country_name.
    remove_index :points, column: :user_id, algorithm: :concurrently, if_exists: true

    # index_points_on_timestamp (1,338 MB) is redundant:
    # Every query filtering on timestamp is already scoped to a user,
    # so the composite (user_id, timestamp) index covers all use cases.
    remove_index :points, column: :timestamp, algorithm: :concurrently, if_exists: true

    # index_track_segments_on_track_id is redundant:
    # Covered by (track_id, start_index, end_index) and
    # (track_id, transportation_mode) composite indexes.
    remove_index :track_segments, column: :track_id, algorithm: :concurrently, if_exists: true

    # index_track_segments_on_transportation_mode is low-selectivity:
    # Only 11 enum values, rarely queried alone. All queries are
    # already covered by (track_id, transportation_mode) composite.
    remove_index :track_segments, column: :transportation_mode, algorithm: :concurrently, if_exists: true
  end
end

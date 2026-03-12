# frozen_string_literal: true

class AddCompositeIndexesAndDropLowSelectivity < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # New composite index: 9 call sites do track.points.order(:timestamp),
    # currently sorting in memory after track_id index scan.
    add_index :points, %i[track_id timestamp],
              name: :idx_points_track_id_timestamp,
              algorithm: :concurrently,
              if_not_exists: true

    # New composite index: multiple queries filter tracks by user + time
    # (IndexQuery, last_for_day, ParallelGenerator, BoundaryDetector).
    add_index :tracks, %i[user_id start_at],
              name: :idx_tracks_user_id_start_at,
              algorithm: :concurrently,
              if_not_exists: true

    # Drop low-selectivity partial index:
    # 97.7% of points have reverse_geocoded_at IS NOT NULL, making this
    # partial index nearly full-size with no filtering benefit.
    # Queries using .reverse_geocoded scope are always user-scoped and
    # will use (user_id, timestamp) index with a heap filter instead.
    # The separate index_points_on_not_reverse_geocoded (WHERE IS NULL)
    # remains and efficiently covers the 2.3% non-geocoded points.
    remove_index :points,
                 column: %i[user_id reverse_geocoded_at],
                 name: :index_points_on_user_id_and_reverse_geocoded_at,
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :points, %i[user_id reverse_geocoded_at],
              name: :index_points_on_user_id_and_reverse_geocoded_at,
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :tracks, name: :idx_tracks_user_id_start_at, algorithm: :concurrently, if_exists: true
    remove_index :points, name: :idx_points_track_id_timestamp, algorithm: :concurrently, if_exists: true
  end
end

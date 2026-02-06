# frozen_string_literal: true

# Removes duplicate Track records that share the same (user_id, start_at, end_at).
#
# Keeps the newest track (highest id) for each unique combination and deletes
# the rest, including their orphaned track_segments.
#
# This addresses a bug where Tracks::DailyGenerationJob created duplicate tracks
# because ParallelGenerator only cleaned existing tracks in :bulk mode, not :daily.
class Tracks::Deduplicator
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    count_before = user.tracks.count
    return 0 unless duplicates_exist?

    deleted = ActiveRecord::Base.transaction do
      delete_orphaned_segments
      delete_duplicate_tracks
    end

    Rails.logger.info "[Tracks::Deduplicator] Removed #{deleted} duplicate tracks for user #{user.id}" \
                      " (#{count_before} -> #{count_before - deleted})"
    deleted
  end

  private

  def duplicates_exist?
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user.id }])
        SELECT EXISTS (
          SELECT 1 FROM tracks
          WHERE user_id = :user_id
          GROUP BY start_at, end_at
          HAVING COUNT(*) > 1
        )
      SQL
    )
  end

  # IDs to keep: the maximum id per (start_at, end_at) group
  def keeper_ids_subquery
    ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user.id }])
      SELECT MAX(id) FROM tracks
      WHERE user_id = :user_id
      GROUP BY start_at, end_at
    SQL
  end

  def delete_orphaned_segments
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user.id }])
        DELETE FROM track_segments
        WHERE track_id IN (
          SELECT id FROM tracks
          WHERE user_id = :user_id
            AND id NOT IN (#{keeper_ids_subquery})
        )
      SQL
    )
  end

  def delete_duplicate_tracks
    result = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user.id }])
        DELETE FROM tracks
        WHERE user_id = :user_id
          AND id NOT IN (#{keeper_ids_subquery})
      SQL
    )

    result.cmd_tuples
  end
end

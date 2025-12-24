# frozen_string_literal: true

class AddCompositeIndexToStats < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 1000

  def change
    # Clean up duplicate stats records before creating unique index.
    # Keep the most recent record (highest id) for each (user_id, year, month) combination.
    # Process in batches to avoid locking the table for too long on large datasets.

    # First, count total duplicates for logging
    total_duplicates = execute(<<-SQL.squish).first['count'].to_i
      SELECT COUNT(*) as count
      FROM stats s1
      WHERE EXISTS (
        SELECT 1 FROM stats s2
        WHERE s2.user_id = s1.user_id
          AND s2.year = s1.year
          AND s2.month = s1.month
          AND s2.id > s1.id
      )
    SQL

    if total_duplicates.positive?
      Rails.logger.info("Found #{total_duplicates} duplicate stats records. Starting cleanup in batches of #{BATCH_SIZE}...")
    end

    deleted_count = 0
    loop do
      # Delete duplicates in batches - keep highest ID for each (user_id, year, month)
      batch_deleted = execute(<<-SQL.squish).cmd_tuples
        DELETE FROM stats s1
        WHERE EXISTS (
          SELECT 1 FROM stats s2
          WHERE s2.user_id = s1.user_id
            AND s2.year = s1.year
            AND s2.month = s1.month
            AND s2.id > s1.id
        )
        LIMIT #{BATCH_SIZE}
      SQL

      break if batch_deleted == 0

      deleted_count += batch_deleted
      Rails.logger.info("Cleaned up #{deleted_count}/#{total_duplicates} duplicate stats records")
    end

    Rails.logger.info("Completed cleanup: removed #{deleted_count} duplicate stats records") if deleted_count > 0

    # Add composite index for the most common stats lookup pattern:
    # Stat.find_or_initialize_by(year:, month:, user:)
    # This query is called on EVERY stats calculation
    #
    # Using algorithm: :concurrently to avoid locking the table during index creation
    # This is crucial for production deployments with existing data
    add_index :stats, %i[user_id year month],
              name: 'index_stats_on_user_id_year_month',
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true

    # Trigger stats recalculation for all users after cleanup and index creation
    # This ensures all stats are up-to-date and consistent with the new unique constraint
    BulkStatsCalculatingJob.perform_later
  end
end

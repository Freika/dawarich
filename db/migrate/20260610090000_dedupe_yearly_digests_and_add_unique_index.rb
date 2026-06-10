# frozen_string_literal: true

class DedupeYearlyDigestsAndAddUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    loop do
      duplicate_ids = execute(<<~SQL).field_values('id')
        SELECT id FROM digests
        WHERE month IS NULL
          AND id NOT IN (
            SELECT MIN(id) FROM digests
            WHERE month IS NULL
            GROUP BY user_id, year, period_type
          )
        LIMIT 1000
      SQL

      break if duplicate_ids.empty?

      execute("DELETE FROM digests WHERE id IN (#{duplicate_ids.join(',')})")
      Rails.logger.info("Removed #{duplicate_ids.size} duplicate yearly digests")
    end

    execute(<<~SQL)
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_digests_on_user_year_period_type_monthless
      ON digests (user_id, year, period_type)
      WHERE month IS NULL
    SQL
  end

  def down
    execute('DROP INDEX CONCURRENTLY IF EXISTS index_digests_on_user_year_period_type_monthless')
  end
end

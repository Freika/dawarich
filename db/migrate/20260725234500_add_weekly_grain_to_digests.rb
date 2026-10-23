# frozen_string_literal: true

class AddWeeklyGrainToDigests < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  WEEKLY_PERIOD_TYPE = 2

  def up
    add_column :digests, :week, :integer unless column_exists?(:digests, :week)

    execute(<<~SQL)
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_digests_on_user_year_period_type_yearly
      ON digests (user_id, year, period_type)
      WHERE month IS NULL AND period_type <> #{WEEKLY_PERIOD_TYPE}
    SQL

    execute(<<~SQL)
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_digests_on_user_year_week_weekly
      ON digests (user_id, year, week, period_type)
      WHERE period_type = #{WEEKLY_PERIOD_TYPE}
    SQL

    execute('DROP INDEX CONCURRENTLY IF EXISTS index_digests_on_user_year_period_type_monthless')
  end

  def down
    execute("DELETE FROM digests WHERE period_type = #{WEEKLY_PERIOD_TYPE}")

    execute('DROP INDEX CONCURRENTLY IF EXISTS index_digests_on_user_year_week_weekly')
    execute('DROP INDEX CONCURRENTLY IF EXISTS index_digests_on_user_year_period_type_yearly')

    execute(<<~SQL)
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_digests_on_user_year_period_type_monthless
      ON digests (user_id, year, period_type)
      WHERE month IS NULL
    SQL

    remove_column :digests, :week if column_exists?(:digests, :week)
  end
end

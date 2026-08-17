# frozen_string_literal: true

class DropSupersededPointsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  REPLACEMENT_INDEX = 'index_points_on_user_id_timestamp_lonlat'

  def up
    # A nonzero lock_timeout aborts CONCURRENTLY's wait for concurrent
    # transactions to finish, leaving the boot migration failed.
    execute 'SET lock_timeout = 0'

    drop_invalid_indexes_on_points!
    ensure_replacement_index_usable!

    remove_index :points, name: 'index_points_on_lonlat_timestamp_user_id',
                          algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'index_points_on_user_id_and_timestamp',
                          algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'idx_points_user_country_name',
                          algorithm: :concurrently, if_exists: true
  end

  def down
    execute 'SET lock_timeout = 0'

    add_index :points, %i[lonlat timestamp user_id],
              unique: true,
              name: 'index_points_on_lonlat_timestamp_user_id',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :points, %i[user_id timestamp],
              order: { timestamp: :desc },
              name: 'index_points_on_user_id_and_timestamp',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :points, %i[user_id country_name],
              name: 'idx_points_user_country_name',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def ensure_replacement_index_usable!
    usable = replacement_index_valid?

    # An interrupted concurrent build leaves the index present but invalid,
    # while `if_not_exists: true` lets its migration report success anyway.
    if usable == false
      repair_replacement_index!
      usable = replacement_index_valid?
    end

    return if usable

    raise ActiveRecord::MigrationError, <<~MESSAGE
      #{REPLACEMENT_INDEX} is missing on `points`, or invalid and could not be
      rebuilt automatically.

      Dropping the superseded indexes now would leave `points` with no unique
      index on (user_id, timestamp, lonlat), which every point upsert relies on
      for ON CONFLICT. All ingestion (OwnTracks, Overland, Traccar, imports)
      would fail with "there is no unique or exclusion constraint matching the
      ON CONFLICT specification", and duplicate protection would be lost.

      Repair it first, then re-run this migration:

        DROP INDEX CONCURRENTLY IF EXISTS #{REPLACEMENT_INDEX};
        CREATE UNIQUE INDEX CONCURRENTLY #{REPLACEMENT_INDEX}
          ON points (user_id, timestamp, lonlat);
    MESSAGE
  end

  # true = valid, false = present but invalid, nil = absent
  def replacement_index_valid?
    connection.select_value(<<~SQL)
      SELECT i.indisvalid
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'points' AND c.relname = '#{REPLACEMENT_INDEX}'
    SQL
  end

  def repair_replacement_index!
    Rails.logger.info("Rebuilding invalid index on points: #{REPLACEMENT_INDEX}")
    execute "REINDEX INDEX CONCURRENTLY #{connection.quote_table_name(REPLACEMENT_INDEX)}"
  rescue ActiveRecord::StatementInvalid => e
    # Fall through to the curated error: e.g. duplicate rows make the unique
    # rebuild impossible without manual intervention.
    Rails.logger.warn("Rebuilding #{REPLACEMENT_INDEX} failed: #{e.message}")
  end

  def drop_invalid_indexes_on_points!
    invalid = connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'points' AND NOT i.indisvalid
        AND c.relname <> '#{REPLACEMENT_INDEX}'
    SQL

    invalid.each do |name|
      Rails.logger.info("Dropping invalid index on points: #{name}")
      execute "DROP INDEX CONCURRENTLY IF EXISTS #{connection.quote_table_name(name)}"
    end
  end
end

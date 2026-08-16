# frozen_string_literal: true

class DropSupersededPointsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    drop_invalid_indexes_on_points!

    remove_index :points, name: 'index_points_on_lonlat_timestamp_user_id',
                          algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'index_points_on_user_id_and_timestamp',
                          algorithm: :concurrently, if_exists: true
    remove_index :points, name: 'idx_points_user_country_name',
                          algorithm: :concurrently, if_exists: true
  end

  def down
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

  def drop_invalid_indexes_on_points!
    invalid = connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'points' AND NOT i.indisvalid
    SQL

    invalid.each do |name|
      Rails.logger.info("Dropping invalid index on points: #{name}")
      execute "DROP INDEX CONCURRENTLY IF EXISTS #{connection.quote_table_name(name)}"
    end
  end
end

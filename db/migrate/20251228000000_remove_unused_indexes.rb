# frozen_string_literal: true

class RemoveUnusedIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    drop_invalid_indexes_on_points!

    remove_index :points, :geodata, algorithm: :concurrently, if_exists: true
    remove_index :points, %i[latitude longitude], algorithm: :concurrently, if_exists: true
    remove_index :points, :altitude, algorithm: :concurrently, if_exists: true
    remove_index :points, :city, algorithm: :concurrently, if_exists: true
    remove_index :points, :country_name, algorithm: :concurrently, if_exists: true
    remove_index :points, :battery_status, algorithm: :concurrently, if_exists: true
    remove_index :points, :connection, algorithm: :concurrently, if_exists: true
    remove_index :points, :trigger, algorithm: :concurrently, if_exists: true
    remove_index :points, :battery, algorithm: :concurrently, if_exists: true
    remove_index :points, :country, algorithm: :concurrently, if_exists: true
    remove_index :points, :external_track_id, algorithm: :concurrently, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
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

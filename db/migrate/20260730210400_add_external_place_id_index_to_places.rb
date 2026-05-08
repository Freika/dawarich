# frozen_string_literal: true

class AddExternalPlaceIdIndexToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_places_user_external_place_id'

  def up
    drop_invalid_index(:places, INDEX_NAME)
    return if index_name_exists?(:places, INDEX_NAME)

    execute(<<~SQL.squish)
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{INDEX_NAME}
        ON places (user_id, ((geodata ->> 'external_place_id')))
        WHERE (geodata ->> 'external_place_id') IS NOT NULL
    SQL
  end

  def down
    return unless index_name_exists?(:places, INDEX_NAME)

    execute("DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME}")
  end

  private

  def drop_invalid_index(table, name)
    invalid = select_value(<<~SQL.squish)
      SELECT 1 FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{name}' AND i.indisvalid = false
    SQL
    return if invalid.nil?

    remove_index table, name: name, algorithm: :concurrently
  end
end

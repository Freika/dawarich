# frozen_string_literal: true

class AddUniqueIndexToTrackSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_track_segments_track_start_index_unique'

  def up
    drop_invalid_index(:track_segments, INDEX_NAME)
    return if index_name_exists?(:track_segments, INDEX_NAME)

    build_index
  rescue ActiveRecord::RecordNotUnique
    # A segment written between the dedupe migration and this build fails it.
    # The dedupe is already recorded and never runs again, so without this every
    # later boot would fail on the same rows forever.
    drop_invalid_index(:track_segments, INDEX_NAME)
    execute(<<~SQL.squish)
      DELETE FROM track_segments WHERE id IN (
        SELECT id FROM (
          SELECT id, row_number() OVER (PARTITION BY track_id, start_index ORDER BY id) AS position
          FROM track_segments
        ) ranked WHERE ranked.position > 1
      )
    SQL
    build_index
  end

  def down
    return unless index_name_exists?(:track_segments, INDEX_NAME)

    remove_index :track_segments, name: INDEX_NAME, algorithm: :concurrently
  end

  private

  def build_index
    add_index :track_segments, %i[track_id start_index],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

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

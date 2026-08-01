# frozen_string_literal: true

class AddUniqueIndexToVisits < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_visits_user_started_at_place_unique'

  def up
    drop_invalid_index(:visits, INDEX_NAME)
    return if index_name_exists?(:visits, INDEX_NAME)

    add_index :visits, %i[user_id started_at place_id],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:visits, INDEX_NAME)

    remove_index :visits, name: INDEX_NAME, algorithm: :concurrently
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

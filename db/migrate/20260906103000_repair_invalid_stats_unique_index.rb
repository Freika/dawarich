# frozen_string_literal: true

class RepairInvalidStatsUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_stats_on_user_id_year_month'
  BATCH_SIZE = 1000

  def up
    valid = select_value(<<~SQL)
      SELECT i.indisvalid
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      WHERE i.indrelid = 'stats'::regclass AND c.relname = '#{INDEX_NAME}'
    SQL
    return if valid

    loop do
      deleted = execute(<<~SQL).cmd_tuples
        DELETE FROM stats
        WHERE id IN (
          SELECT s1.id FROM stats s1
          WHERE EXISTS (
            SELECT 1 FROM stats s2
            WHERE s2.user_id = s1.user_id
              AND s2.year = s1.year
              AND s2.month = s1.month
              AND s2.id > s1.id
          )
          LIMIT #{BATCH_SIZE}
        )
      SQL
      break if deleted.zero?
    end

    remove_index :stats, name: INDEX_NAME, algorithm: :concurrently if valid == false
    add_index :stats, %i[user_id year month], name: INDEX_NAME, unique: true, algorithm: :concurrently
  end

  def down; end
end

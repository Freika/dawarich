# frozen_string_literal: true

class AddAchievementWatermarkIndexToPoints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_points_achievement_watermark'
  PREDICATE = 'lonlat IS NOT NULL AND anomaly IS DISTINCT FROM TRUE'

  def up
    execute 'SET lock_timeout = 0'

    invalid = select_value(<<~SQL)
      SELECT NOT i.indisvalid
      FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{INDEX_NAME}'
    SQL
    remove_index :points, name: INDEX_NAME, algorithm: :concurrently, if_exists: true if invalid

    add_index :points, %i[user_id id], include: :timestamp, where: PREDICATE,
                                      name: INDEX_NAME, algorithm: :concurrently, if_not_exists: true
  ensure
    execute 'RESET lock_timeout'
  end

  def down
    remove_index :points, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end

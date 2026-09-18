# frozen_string_literal: true

class AddAchievementWatermarkIndexToPoints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_points_achievement_watermark'
  PREDICATE = 'lonlat IS NOT NULL AND anomaly IS DISTINCT FROM TRUE'

  def up
    add_index :points, %i[user_id id], include: :timestamp, where: PREDICATE,
                                      name: INDEX_NAME, algorithm: :concurrently
  end

  def down
    remove_index :points, name: INDEX_NAME, algorithm: :concurrently
  end
end

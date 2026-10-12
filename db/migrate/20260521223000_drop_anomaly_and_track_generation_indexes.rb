# frozen_string_literal: true

class DropAnomalyAndTrackGenerationIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEXES = %w[
    index_points_on_not_anomaly
    idx_points_track_generation
  ].freeze

  def up
    Rails.logger.info '[DropAnomalyAndTrackGenerationIndexes] starting'
    INDEXES.each do |name|
      Rails.logger.info "[DropAnomalyAndTrackGenerationIndexes] dropping #{name}"
      execute "DROP INDEX CONCURRENTLY IF EXISTS #{name}"
    end
    Rails.logger.info '[DropAnomalyAndTrackGenerationIndexes] done'
  end

  def down
    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_points_on_not_anomaly
        ON points (anomaly)
        WHERE anomaly IS NOT TRUE
    SQL

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_points_track_generation
        ON points (user_id, timestamp, track_id)
    SQL
  end
end

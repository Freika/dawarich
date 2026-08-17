# frozen_string_literal: true

# Seeds point_sources / point_motions from existing points and stamps
# source_id / motion_id, one id-range batch per invocation, re-enqueueing
# itself until the whole table is covered. Resumable from any cursor and
# idempotent: seeding upserts by digest, stamping only touches NULL FKs.
class DataMigrations::BackfillPointDimensionsJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000
  PAUSE = 5.seconds

  def perform(start_id = nil)
    start_id ||= Point.minimum(:id)
    return if start_id.nil?

    end_id = start_id + BATCH_SIZE - 1

    seed_sources(start_id, end_id)
    stamp_sources(start_id, end_id)
    seed_motions(start_id, end_id)
    stamp_motions(start_id, end_id)

    max_id = Point.maximum(:id)
    return if max_id.nil? || end_id >= max_id

    self.class.set(wait: PAUSE).perform_later(end_id + 1)
  end

  private

  def execute_sanitized(sql, *binds)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([sql, *binds])
    )
  end

  def combo_column_list
    PointSource::COMBO_COLUMNS
      .map { |column| ActiveRecord::Base.connection.quote_column_name(column) }
      .join(', ')
  end

  def seed_sources(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      INSERT INTO point_sources (digest, #{combo_column_list}, created_at, updated_at)
      SELECT #{PointSource.digest_sql('t')}, #{combo_column_list}, NOW(), NOW()
      FROM (
        SELECT DISTINCT #{combo_column_list}
        FROM points
        WHERE id BETWEEN ? AND ?
      ) t
      ON CONFLICT (digest) DO NOTHING
    SQL
  end

  def stamp_sources(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      UPDATE points p
      SET source_id = ps.id
      FROM point_sources ps
      WHERE p.id BETWEEN ? AND ?
        AND p.source_id IS NULL
        AND ps.digest = #{PointSource.digest_sql('p')}
    SQL
  end

  def seed_motions(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      INSERT INTO point_motions (digest, motion_data, created_at, updated_at)
      SELECT #{PointMotion.digest_sql('t')}, t.motion_data, NOW(), NOW()
      FROM (
        SELECT DISTINCT motion_data
        FROM points
        WHERE id BETWEEN ? AND ? AND motion_data IS NOT NULL
      ) t
      ON CONFLICT (digest) DO NOTHING
    SQL
  end

  def stamp_motions(start_id, end_id)
    execute_sanitized(<<~SQL.squish, start_id, end_id)
      UPDATE points p
      SET motion_id = pm.id
      FROM point_motions pm
      WHERE p.id BETWEEN ? AND ?
        AND p.motion_id IS NULL
        AND p.motion_data IS NOT NULL
        AND pm.digest = #{PointMotion.digest_sql('p')}
    SQL
  end
end

# frozen_string_literal: true

class Points::TrackerIdBackfiller
  BATCH_SIZE = 5_000
  LEGACY_CONSTANTS = %w[google-maps-timeline-export google-maps-phone-timeline-export].freeze

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    total = 0
    cursor = 0

    loop do
      updated, max_id = update_batch(cursor)
      break if updated.zero?

      total += updated
      cursor = max_id
    end

    Rails.logger.info("[Points::TrackerIdBackfiller] user_id=#{user.id} backfilled=#{total}") if total.positive?

    total
  end

  private

  def update_batch(cursor)
    sql = <<~SQL.squish
      WITH batch AS (
        SELECT id FROM points
        WHERE user_id = #{user.id.to_i}
          AND id > #{cursor.to_i}
          AND (
            tracker_id IS NULL
            OR tracker_id IN (#{LEGACY_CONSTANTS.map { |c| "'#{c}'" }.join(', ')})
          )
          AND (
            length(btrim(raw_data->>'deviceTag')) > 0
            OR length(btrim(raw_data->>'tid')) > 0
            OR import_id IS NOT NULL
          )
        ORDER BY id
        LIMIT #{BATCH_SIZE}
      ),
      bounds AS (SELECT MAX(id) AS max_id FROM batch)
      UPDATE points
      SET
        tracker_id = (
          CASE
            WHEN length(btrim(points.raw_data->>'deviceTag')) > 0
              THEN 'google-records-device-' || btrim(points.raw_data->>'deviceTag')
            WHEN length(btrim(points.raw_data->>'tid')) > 0
              THEN btrim(points.raw_data->>'tid')
            ELSE 'legacy-import-' || points.import_id::text
          END
        ),
        updated_at = NOW()
      FROM batch, bounds
      WHERE points.id = batch.id
      RETURNING bounds.max_id
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, 'TrackerIdBackfill')
    rows = result.rows
    return [0, cursor] if rows.empty?

    [rows.length, rows.first.first.to_i]
  end
end

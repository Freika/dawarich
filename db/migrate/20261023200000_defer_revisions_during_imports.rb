# frozen_string_literal: true

class DeferRevisionsDuringImports < ActiveRecord::Migration[8.1]
  SETTING = 'dawarich.defer_revisions'
  POINT_MONTH = "date_trunc('month', to_timestamp(timestamp) AT TIME ZONE 'UTC')::date"
  POINT_SOURCES = {
    insert: 'SELECT user_id, timestamp FROM new_points',
    update: 'SELECT user_id, timestamp FROM old_points UNION ALL SELECT user_id, timestamp FROM new_points',
    delete: 'SELECT user_id, timestamp FROM old_points',
    truncate: 'SELECT user_id, timestamp FROM points'
  }.freeze
  TRACK_SOURCES = {
    insert: 'SELECT user_id, start_at, end_at FROM new_tracks',
    update: 'SELECT user_id, start_at, end_at FROM old_tracks UNION ALL ' \
            'SELECT user_id, start_at, end_at FROM new_tracks',
    delete: 'SELECT user_id, start_at, end_at FROM old_tracks',
    truncate: 'SELECT user_id, start_at, end_at FROM tracks'
  }.freeze

  def up
    replace_functions(deferrable: true)
  end

  def down
    replace_functions(deferrable: false)
  end

  private

  def replace_functions(deferrable:)
    POINT_SOURCES.each { |event, source| execute(point_function(event, source, deferrable)) }
    TRACK_SOURCES.each { |event, source| execute(track_function(event, source, deferrable)) }
  end

  def guard(deferrable)
    return '' unless deferrable

    "IF current_setting('#{SETTING}', true) = 'on' THEN RETURN NULL; END IF;\n  "
  end

  def point_function(event, source, deferrable)
    <<~SQL
      CREATE OR REPLACE FUNCTION points_revision_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        #{guard(deferrable)}INSERT INTO point_revisions (user_id, month, revision)
        SELECT user_id, #{POINT_MONTH}, gen_random_uuid()
        FROM (#{source}) AS changed
        WHERE user_id IS NOT NULL AND timestamp IS NOT NULL
        GROUP BY user_id, #{POINT_MONTH}
        ORDER BY user_id, #{POINT_MONTH}
        ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision;
        RETURN NULL;
      END;
      $$;
    SQL
  end

  def track_function(event, source, deferrable)
    <<~SQL
      CREATE OR REPLACE FUNCTION tracks_revision_#{event}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        #{guard(deferrable)}INSERT INTO track_revisions (user_id, month, revision)
        SELECT changed.user_id, months.month::date, gen_random_uuid()
        FROM (#{source}) AS changed
        CROSS JOIN LATERAL generate_series(
          date_trunc('month', changed.start_at), date_trunc('month', changed.end_at), interval '1 month'
        ) AS months(month)
        WHERE changed.user_id IS NOT NULL AND changed.start_at IS NOT NULL AND changed.end_at IS NOT NULL
        GROUP BY changed.user_id, months.month
        ORDER BY changed.user_id, months.month
        ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision;
        RETURN NULL;
      END;
      $$;
    SQL
  end
end

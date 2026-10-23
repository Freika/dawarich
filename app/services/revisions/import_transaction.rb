# frozen_string_literal: true

module Revisions
  class ImportTransaction
    SETTING = 'dawarich.defer_revisions'

    BUMP_POINTS = <<~SQL.squish
      WITH RECURSIVE bounds AS (
        SELECT MIN(timestamp) AS first_ts, MAX(timestamp) AS last_ts FROM points WHERE %<scope>s
      ), months AS (
        SELECT date_trunc('month', to_timestamp(first_ts) AT TIME ZONE 'UTC') AS month FROM bounds
        WHERE first_ts IS NOT NULL
        UNION ALL
        SELECT (
          SELECT date_trunc('month', to_timestamp(points.timestamp) AT TIME ZONE 'UTC')
          FROM points
          WHERE points.user_id = :user_id
            AND points.timestamp >= EXTRACT(EPOCH FROM (months.month + interval '1 month') AT TIME ZONE 'UTC')::bigint
            AND points.timestamp <= (SELECT last_ts FROM bounds)
          ORDER BY points.timestamp
          LIMIT 1
        )
        FROM months
        WHERE months.month IS NOT NULL
      )
      INSERT INTO point_revisions (user_id, month, revision)
      SELECT :user_id, months.month::date, gen_random_uuid() FROM months
      WHERE months.month IS NOT NULL
      ORDER BY months.month
      ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision
    SQL

    BUMP_TRACKS = <<~SQL.squish
      INSERT INTO track_revisions (user_id, month, revision)
      SELECT :user_id, months.month::date, gen_random_uuid()
      FROM (
        SELECT DISTINCT generate_series(date_trunc('month', start_at), date_trunc('month', end_at), interval '1 month')
          AS month
        FROM tracks
        WHERE user_id = :user_id
      ) AS months
      ORDER BY months.month
      ON CONFLICT (user_id, month) DO UPDATE SET revision = EXCLUDED.revision
    SQL

    def self.call(user_id, import_id: nil, &)
      new(user_id, import_id:).call(&)
    end

    def initialize(user_id, import_id: nil)
      @user_id = user_id
      @import_id = import_id
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        previous = connection.select_value("SELECT current_setting('#{SETTING}', true)").presence || 'off'
        defer_revisions('on')
        value = yield
        defer_revisions(previous)
        bump(BUMP_POINTS)
        bump(BUMP_TRACKS) unless import_id
        value
      end
    end

    private

    attr_reader :user_id, :import_id

    def defer_revisions(value)
      connection.execute("SET LOCAL #{SETTING} = #{connection.quote(value)}")
    end

    def bump(template)
      sql = format(template, scope: import_id ? 'import_id = :import_id' : 'user_id = :user_id')
      connection.exec_update(ActiveRecord::Base.sanitize_sql([sql, { user_id:, import_id: }]))
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end

# frozen_string_literal: true

module Maps
  # Aggregate original samples, never simplified tile geometry or daily totals.
  class RangeStatistics
    def initialize(user, start_at:, end_at:, import_id: nil)
      @user = user
      @start_at = start_at
      @end_at = end_at
      @import_id = import_id
    end

    def call
      masker = PrivacyZoneMasker.new(user)
      revision = Points::Revision.for_user(user.id, start_at:, end_at:)
      track_revision = Tracks::Revision.for_user(user.id, start_at:, end_at:)
      key = ['maps/range_statistics/v1', user.id, revision, track_revision, start_at, end_at, import_id,
             user.entitlements.data_window_start&.to_date, user.safe_settings.minutes_between_routes,
             masker.fingerprint]
      Rails.cache.fetch(key, expires_in: 5.minutes) { aggregate(masker) }
    end

    private

    attr_reader :user, :start_at, :end_at, :import_id

    def aggregate(masker)
      scope = user.scoped_points.not_anomaly.where(timestamp: start_at..end_at)
      scope = scope.where(import_id:) if import_id.present?
      scope = scope.reselect(:id, :timestamp, :lonlat, :tracker_id, :track_id).reorder(nil)
      # Match map/track time gaps. Recorded track IDs also preserve server-side
      # stationary-stop boundaries; untracked samples need no Track/Trip creation.
      seconds = user.safe_settings.minutes_between_routes.to_i * 60
      sql = <<~SQL
        -- Keep masked samples in the window so removing one cannot create a
        -- new edge between its formerly non-adjacent visible neighbours.
        WITH samples AS (
          SELECT *, NOT #{masker.within_sql('lonlat')} AS visible FROM (#{scope.to_sql}) original
        ), edges AS (
          SELECT *,
            LAG(lonlat) OVER ordered AS previous_lonlat,
            LAG(timestamp) OVER ordered AS previous_timestamp,
            LAG(track_id) OVER ordered AS previous_track_id,
            LAG(visible) OVER ordered AS previous_visible
          FROM samples
          WINDOW ordered AS (PARTITION BY tracker_id ORDER BY timestamp, id)
        )
        SELECT COUNT(*) FILTER (WHERE visible) AS points,
          COALESCE(SUM(CASE
            WHEN visible AND previous_visible AND track_id IS NOT DISTINCT FROM previous_track_id
              AND timestamp - previous_timestamp BETWEEN 0 AND #{seconds}
            THEN ST_Distance(lonlat::geography, previous_lonlat::geography)
            ELSE 0 END), 0) AS distance_meters
        FROM edges
      SQL
      row = Point.transaction do
        Point.connection.execute("SET LOCAL statement_timeout = '5s'")
        Point.connection.select_one(sql)
      end
      { points: row['points'].to_i, distance_meters: row['distance_meters'].to_f }
    end
  end
end

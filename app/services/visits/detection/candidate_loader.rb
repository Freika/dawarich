# frozen_string_literal: true

module Visits
  module Detection
    # Loads the raw evidence for one detection window: candidate points and
    # the transportation segments overlapping it. Unlike the retired
    # StayPointDetector query, points already owned by a visit are INCLUDED —
    # detection is a pure function of raw points, never of prior output.
    class CandidateLoader
      MAX_CANDIDATE_POINTS = 100_000
      QUERY_TIMEOUT_MS = 30_000

      Pt = Struct.new(:id, :lat, :lon, :timestamp, :accuracy)
      Seg = Struct.new(:mode, :confidence, :corrected, :start_ts, :end_ts)

      def initialize(user, start_at:, end_at:, policy:)
        @user = user
        @start_at = start_at.to_i
        @end_at = end_at.to_i
        @policy = policy
      end

      def call
        candidate_count = count_candidate_points
        if candidate_count > MAX_CANDIDATE_POINTS
          Rails.logger.warn(
            "[Visits::Detection::CandidateLoader skip] user_id=#{user.id} " \
            "range=#{start_at}..#{end_at} candidate_points=#{candidate_count} max=#{MAX_CANDIDATE_POINTS}"
          )
          return { points: [], segments: [], skipped: true }
        end

        { points: load_points, segments: load_segments, skipped: false }
      end

      private

      attr_reader :user, :start_at, :end_at, :policy

      def candidate_scope
        Point.where(user_id: user.id)
             .where(timestamp: start_at..end_at)
             .where.not(lonlat: nil)
             .where('anomaly IS NULL OR anomaly = FALSE')
             .where("NOT #{Points::NullIsland.sql_predicate}")
      end

      def count_candidate_points
        candidate_scope.count
      end

      def load_points
        sql = ActiveRecord::Base.sanitize_sql_array(
          [
            <<~SQL.squish,
              SELECT id,
                     ST_Y(lonlat::geometry) AS lat,
                     ST_X(lonlat::geometry) AS lon,
                     timestamp,
                     accuracy
              FROM points
              WHERE user_id = ?
                AND timestamp BETWEEN ? AND ?
                AND lonlat IS NOT NULL
                AND (anomaly IS NULL OR anomaly = FALSE)
                AND NOT (ST_X(lonlat::geometry) = 0 AND ST_Y(lonlat::geometry) = 0)
              ORDER BY timestamp ASC
            SQL
            user.id, start_at, end_at
          ]
        )

        conn = ActiveRecord::Base.connection
        # SET LOCAL binds the timeout to this transaction's backend so it
        # survives PgBouncer transaction pooling.
        conn.transaction do
          conn.exec_query("SET LOCAL statement_timeout = #{QUERY_TIMEOUT_MS}", 'CandidateLoader Timeout')
          conn.exec_query(sql, 'CandidateLoader Points').map do |row|
            Pt.new(row['id'].to_i, row['lat'].to_f, row['lon'].to_f, row['timestamp'].to_i, row['accuracy']&.to_i)
          end
        end
      end

      def load_segments
        TrackSegment
          .joins(:track)
          .where(tracks: { user_id: user.id })
          .where.not(start_at: nil).where.not(end_at: nil)
          .where(start_at: ..Time.zone.at(end_at))
          .where(end_at: Time.zone.at(start_at)..)
          .order(:start_at)
          .map do |segment|
            Seg.new(
              segment.transportation_mode,
              segment.confidence_score,
              segment.corrected_at.present?,
              segment.start_at.to_i,
              segment.end_at.to_i
            )
          end
      end
    end
  end
end

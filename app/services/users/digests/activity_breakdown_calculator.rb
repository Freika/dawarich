# frozen_string_literal: true

module Users
  module Digests
    class ActivityBreakdownCalculator
      STATIONARY_PROXIMITY_METERS = 100
      MAXIMUM_STATIONARY_GAP_SECONDS = 24.hours.to_i
      MINIMUM_FLIGHT_SPEED_KMH = 150
      MINIMUM_FLIGHT_DISTANCE_KM = 100
      MAXIMUM_FLIGHT_GAP_SECONDS = 24.hours.to_i

      def initialize(user, year, month = nil)
        @user = user
        @year = year.to_i
        @month = month&.to_i
      end

      def call
        duration_by_mode = fetch_durations
        add_inter_track_time(duration_by_mode)
        calculate_breakdown(duration_by_mode)
      end

      private

      attr_reader :user, :year, :month

      def fetch_durations
        scope = TrackSegment.joins(:track).where(tracks: { user_id: user.id })
        scope = scope.where('tracks.start_at >= ? AND tracks.start_at <= ?', start_time, end_time)
        scope.group(:transportation_mode).sum(:duration)
      end

      def add_inter_track_time(duration_by_mode)
        boundary_points = fetch_track_boundary_points
        return if boundary_points.size < 2

        stationary_time, flying_time = calculate_inter_track_times(boundary_points)
        add_duration(duration_by_mode, 'stationary', stationary_time)
        add_duration(duration_by_mode, 'flying', flying_time)
      end

      def add_duration(duration_by_mode, mode, time)
        return unless time.positive?

        duration_by_mode[mode] = (duration_by_mode[mode] || 0) + time
      end

      def calculate_inter_track_times(boundary_points)
        boundary_points.each_cons(2).each_with_object([0, 0]) do |pair, totals|
          gap_result = classify_gap(pair)
          totals[0] += gap_result[:stationary]
          totals[1] += gap_result[:flying]
        end
      end

      def classify_gap(track_pair)
        track1_data, track2_data = track_pair
        gap_seconds = track2_data[:start_at].to_i - track1_data[:end_at].to_i
        return { stationary: 0, flying: 0 } if gap_seconds <= 0

        end_point = track1_data[:end_point]
        start_point = track2_data[:start_point]
        return { stationary: 0, flying: 0 } unless end_point && start_point

        classify_gap_by_distance(gap_seconds, end_point.distance_to_geocoder(start_point, :km))
      end

      def classify_gap_by_distance(gap_seconds, distance_km)
        return { stationary: gap_seconds, flying: 0 } if stationary_gap?(gap_seconds, distance_km)
        return { stationary: 0, flying: gap_seconds } if flying_gap?(gap_seconds, distance_km)

        { stationary: 0, flying: 0 }
      end

      def stationary_gap?(gap_seconds, distance_km)
        gap_seconds <= MAXIMUM_STATIONARY_GAP_SECONDS && (distance_km * 1000) <= STATIONARY_PROXIMITY_METERS
      end

      def flying_gap?(gap_seconds, distance_km)
        gap_seconds <= MAXIMUM_FLIGHT_GAP_SECONDS &&
          distance_km >= MINIMUM_FLIGHT_DISTANCE_KM &&
          (distance_km / (gap_seconds / 3600.0)) >= MINIMUM_FLIGHT_SPEED_KMH
      end

      def fetch_track_boundary_points
        tracks = fetch_tracks_in_range
        return [] if tracks.empty?

        track_ids = tracks.map(&:first)
        build_boundary_data(tracks, fetch_boundary_points(track_ids, 'ASC'), fetch_boundary_points(track_ids, 'DESC'))
      end

      def fetch_tracks_in_range
        user.tracks
            .where(start_at: start_time..end_time)
            .order(:start_at)
            .pluck(:id, :start_at, :end_at)
      end

      def fetch_boundary_points(track_ids, order)
        Point
          .without_raw_data
          .where(track_id: track_ids)
          .select('DISTINCT ON (track_id) track_id, id, lonlat, timestamp')
          .order("track_id, timestamp #{order}")
          .index_by(&:track_id)
      end

      def build_boundary_data(tracks, first_points, last_points)
        tracks.map do |id, s, e|
          { track_id: id, start_at: s, end_at: e, start_point: first_points[id], end_point: last_points[id] }
        end
      end

      def calculate_breakdown(duration_by_mode)
        total = duration_by_mode.values.sum
        return {} if total.zero?

        duration_by_mode.each_with_object({}) do |(mode, duration), result|
          if mode
            result[mode.to_s] =
              { 'duration' => duration.to_i, 'percentage' => ((duration.to_f / total) * 100).round }
          end
        end
      end

      def start_time = month ? Time.zone.local(year, month, 1).beginning_of_month : Time.zone.local(year, 1, 1)
      def end_time = month ? Time.zone.local(year, month, 1).end_of_month : Time.zone.local(year, 12, 31).end_of_year
    end
  end
end

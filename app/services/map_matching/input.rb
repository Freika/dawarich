# frozen_string_literal: true

module MapMatching
  class Input
    Point = Data.define(:id, :timestamp, :lon, :lat, :accuracy) do
      def atlas_shape
        { lat:, lon:, time: timestamp }.tap do |shape|
          shape[:accuracy] = accuracy unless accuracy.nil?
        end
      end

      def coordinates
        [lon, lat]
      end
    end

    Portion = Data.define(
      :key, :transportation_mode, :atlas_mode, :points, :start_index, :end_index
    ) do
      def eligible?
        atlas_mode.present? && points.size >= 2
      end

      def original_coordinates
        points.map(&:coordinates)
      end
    end

    REQUEST_PROFILE = {
      shape_match: 'map_snap',
      format: 'geojson',
      include_directions: false
    }.freeze

    attr_reader :track, :points, :portions, :segment_fingerprint

    def initialize(track)
      @track = track
      @points = load_points
      segments = ordered_segments
      @segment_fingerprint = segments.map { |segment| fingerprint_segment(segment) }
      @portions = build_portions(segments)
    end

    def eligible?
      portions.any?(&:eligible?)
    end

    def fingerprint_payload
      {
        points: points.map(&:atlas_shape),
        segments: segment_fingerprint,
        request: REQUEST_PROFILE
      }
    end

    private

    def load_points
      sql = ::Point.sanitize_sql_array([<<~SQL.squish, track.id])
        SELECT id, timestamp, accuracy,
               ST_X(lonlat::geometry) AS longitude,
               ST_Y(lonlat::geometry) AS latitude
        FROM points
        WHERE track_id = ? AND anomaly IS NOT TRUE
        ORDER BY timestamp ASC, id ASC
      SQL

      ::Point.connection.select_all(sql).map do |row|
        Point.new(
          id: row['id'].to_i,
          timestamp: row['timestamp'].to_i,
          lon: row['longitude'].to_f,
          lat: row['latitude'].to_f,
          accuracy: row['accuracy']&.to_f
        )
      end
    end

    def ordered_segments
      track.track_segments.to_a.sort_by do |segment|
        [segment_start(segment), segment.id || 0]
      end
    end

    def segment_start(segment)
      segment.start_at&.to_f || segment.start_index&.to_f || Float::INFINITY
    end

    def fingerprint_segment(segment)
      {
        start_at: segment.start_at&.to_i,
        end_at: segment.end_at&.to_i,
        start_index: segment.start_index,
        end_index: segment.end_index,
        mode: segment.transportation_mode
      }
    end

    def build_portions(segments)
      return [] if points.size < 2

      edge_owners = points.each_index.take(points.size - 1).map do |index|
        segments.find { |segment| covers_edge?(segment, index) }
      end

      group_edges(edge_owners).map do |owner, start_index, end_edge_index|
        Portion.new(
          key: owner ? "segment:#{owner.id}" : "fallback:#{start_index}",
          transportation_mode: owner&.transportation_mode,
          atlas_mode: ModeMapper.call(owner&.transportation_mode),
          points: points.slice(start_index..(end_edge_index + 1)),
          start_index:,
          end_index: end_edge_index + 1
        )
      end
    end

    def group_edges(edge_owners)
      edge_owners.each_with_index.each_with_object([]) do |(owner, index), groups|
        if groups.any? && groups.last.first == owner
          groups.last[2] = index
        else
          groups << [owner, index, index]
        end
      end
    end

    def covers_edge?(segment, index)
      if segment.start_at && segment.end_at
        first_timestamp = points[index].timestamp
        second_timestamp = points[index + 1].timestamp
        return first_timestamp >= segment.start_at.to_i && second_timestamp <= segment.end_at.to_i
      end

      segment.start_index && segment.end_index &&
        index >= segment.start_index && (index + 1) <= segment.end_index
    end
  end
end

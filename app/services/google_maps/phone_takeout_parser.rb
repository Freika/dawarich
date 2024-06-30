# frozen_string_literal: true

class GoogleMaps::PhoneTakeoutParser
  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import = import
    @user_id = user_id
  end

  def call
    points_data = parse_json

    points = 0

    points_data.compact.each do |point_data|
      next if Point.exists?(
        timestamp: point_data[:timestamp],
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        user_id:
      )

      Point.create(
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        timestamp: point_data[:timestamp],
        raw_data: point_data[:raw_data],
        accuracy: point_data[:accuracy],
        altitude: point_data[:altitude],
        velocity: point_data[:velocity],
        topic: 'Google Maps Phone Timeline Export',
        tracker_id: 'google-maps-phone-timeline-export',
        import_id: import.id,
        user_id:
      )

      points += 1
    end

    doubles = points_data.size - points
    processed = points + doubles

    { raw_points: points_data.size, points:, doubles:, processed: }
  end

  private

  def parse_json
    semantic_segments = import.raw_data['semanticSegments'].flat_map do |segment|
      if segment.key?('timelinePath')
        segment['timelinePath'].map do |point|
          lat, lon = parse_coordinates(point['point'])
          timestamp = DateTime.parse(point['time']).to_i

          point_hash(lat, lon, timestamp, segment)
        end
      elsif segment.key?('visit')
        lat, lon = parse_coordinates(segment['visit']['topCandidate']['placeLocation']['latLng'])
        timestamp = DateTime.parse(segment['startTime']).to_i

        point_hash(lat, lon, timestamp, segment)
      else # activities
        # Some activities don't have start latLng
        next if segment.dig('activity', 'start', 'latLng').nil?

        start_lat, start_lon = parse_coordinates(segment['activity']['start']['latLng'])
        start_timestamp = DateTime.parse(segment['startTime']).to_i
        end_lat, end_lon = parse_coordinates(segment['activity']['end']['latLng'])
        end_timestamp = DateTime.parse(segment['endTime']).to_i

        [
          point_hash(start_lat, start_lon, start_timestamp, segment),
          point_hash(end_lat, end_lon, end_timestamp, segment)
        ]
      end
    end

    raw_signals = import.raw_data['rawSignals'].flat_map do |segment|
      next unless segment.dig('position', 'LatLng')

      lat, lon = parse_coordinates(segment['position']['LatLng'])
      timestamp = DateTime.parse(segment['position']['timestamp']).to_i

      point_hash(lat, lon, timestamp, segment)
    end

    semantic_segments + raw_signals
  end

  def parse_coordinates(coordinates)
    coordinates.split(', ').map { _1.chomp('°') }
  end

  def point_hash(lat, lon, timestamp, raw_data)
    {
      latitude: lat.to_f,
      longitude: lon.to_f,
      timestamp:,
      raw_data:,
      accuracy: raw_data['accuracyMeters'],
      altitude: raw_data['altitudeMeters'],
      velocitu: raw_data['speedMetersPerSecond']
    }
  end
end

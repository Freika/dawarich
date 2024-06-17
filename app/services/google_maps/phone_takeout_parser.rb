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

    points_data.each do |point_data|
      next if Point.exists?(timestamp: point_data[:timestamp])

      Point.create(
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        timestamp: point_data[:timestamp],
        raw_data: point_data[:raw_data],
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
    import.raw_data['semanticSegments'].flat_map do |segment|
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
      end
    end
  end

  def parse_coordinates(coordinates)
    coordinates.split(', ').map { _1.chomp('°') }
  end

  def point_hash(lat, lon, timestamp, raw_data)
    {
      latitude: lat.to_f,
      longitude: lon.to_f,
      timestamp:,
      raw_data:
    }
  end
end

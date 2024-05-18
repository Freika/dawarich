# frozen_string_literal: true

class GoogleMaps::RecordsParser
  attr_reader :import

  def initialize(import)
    @import = import
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
        topic: 'Google Maps Timeline Export',
        tracker_id: 'google-maps-timeline-export',
        import_id: import.id
      )

      points += 1
    end

    doubles = points_data.size - points
    processed = points + doubles

    { raw_points: points_data.size, points:, doubles:, processed: }
  end

  private

  def parse_json
    import.raw_data['locations'].map do |record|
      {
        latitude: record['latitudeE7'].to_f / 10**7,
        longitude: record['longitudeE7'].to_f / 10**7,
        timestamp: DateTime.parse(record['timestamp']).to_i,
        raw_data: record
      }
    end.reject(&:blank?)
  end
end

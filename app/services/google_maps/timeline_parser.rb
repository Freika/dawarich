# frozen_string_literal: true

class GoogleMaps::TimelineParser
  attr_reader :import, :json

  def initialize(import)
    @import = import
    @json = JSON.parse(import.file.download)
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

    { raw_points: points_data.size, points: points, doubles: doubles, processed: processed }
  end

  private

  def parse_json
    json['timelineObjects'].flat_map do |timeline_object|
      if timeline_object['activitySegment'].present?
        if timeline_object['activitySegment']['startLocation'].blank?
          next if timeline_object['activitySegment']['waypointPath'].blank?

          timeline_object['activitySegment']['waypointPath']['waypoints'].map do |waypoint|
            {
              latitude: waypoint['latE7'].to_f / 10**7,
              longitude: waypoint['lngE7'].to_f / 10**7,
              timestamp: DateTime.parse(timeline_object['activitySegment']['duration']['startTimestamp']).to_i,
              raw_data: timeline_object
            }
          end
        else
          {
            latitude: timeline_object['activitySegment']['startLocation']['latitudeE7'].to_f / 10**7,
            longitude: timeline_object['activitySegment']['startLocation']['longitudeE7'].to_f / 10**7,
            timestamp: DateTime.parse(timeline_object['activitySegment']['duration']['startTimestamp']),
            raw_data: timeline_object
          }
        end
      elsif timeline_object['placeVisit'].present?
        {
          latitude: timeline_object['placeVisit']['location']['latitudeE7'].to_f / 10**7,
          longitude: timeline_object['placeVisit']['location']['longitudeE7'].to_f / 10**7,
          timestamp: DateTime.parse(timeline_object['placeVisit']['duration']['startTimestamp']),
          raw_data: timeline_object
        }
      end
    end.reject(&:blank?)
  end
end

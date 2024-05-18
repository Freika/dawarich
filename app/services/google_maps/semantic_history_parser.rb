# frozen_string_literal: true

class GoogleMaps::SemanticHistoryParser
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

    { raw_points: points_data.size, points: points, doubles: doubles, processed: processed }
  end

  private

  def parse_json
    import.raw_data['timelineObjects'].flat_map do |timeline_object|
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
        if timeline_object['placeVisit']['location']['latitudeE7'].present? &&
           timeline_object['placeVisit']['location']['longitudeE7'].present?
          {
            latitude: timeline_object['placeVisit']['location']['latitudeE7'].to_f / 10**7,
            longitude: timeline_object['placeVisit']['location']['longitudeE7'].to_f / 10**7,
            timestamp: DateTime.parse(timeline_object['placeVisit']['duration']['startTimestamp']),
            raw_data: timeline_object
          }
        elsif timeline_object['placeVisit']['otherCandidateLocations'].any?
          point = timeline_object['placeVisit']['otherCandidateLocations'][0]

          next unless point['latitudeE7'].present? && point['longitudeE7'].present?

          {
            latitude: point['latitudeE7'].to_f / 10**7,
            longitude: point['longitudeE7'].to_f / 10**7,
            timestamp: DateTime.parse(timeline_object['placeVisit']['duration']['startTimestamp']),
            raw_data: timeline_object
          }
        else
          next
        end
      end
    end.reject(&:blank?)
  end
end

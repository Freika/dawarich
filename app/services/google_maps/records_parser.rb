# frozen_string_literal: true

class GoogleMaps::RecordsParser
  attr_reader :import

  def initialize(import)
    @import = import
  end

  def call(json)
    data = parse_json(json)

    return if Point.exists?(
      latitude: data[:latitude],
      longitude: data[:longitude],
      timestamp: data[:timestamp],
      user_id: import.user_id
    )

    Point.create(
      latitude: data[:latitude],
      longitude: data[:longitude],
      timestamp: data[:timestamp],
      raw_data: data[:raw_data],
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: import.id,
      user_id: import.user_id
    )
  end

  private

  def parse_json(json)
    {
      latitude: json['latitudeE7'].to_f / 10**7,
      longitude: json['longitudeE7'].to_f / 10**7,
      timestamp: parse_timestamp(json['timestamp'] || json['timestampMs']),
      altitude: json['altitude'],
      velocity: json['velocity'],
      raw_data: json
    }
  end

  def parse_timestamp(timestamp)
    begin
      # if the timestamp is in ISO 8601 format, try to parse it
      DateTime.parse(timestamp).to_time.to_i
    rescue
      if timestamp.to_s.length > 10
        # If the timestamp is in milliseconds, convert to seconds
        timestamp.to_i / 1000
      else
        # If the timestamp is in seconds, return it without change
        timestamp.to_i
      end
    end
  end
end

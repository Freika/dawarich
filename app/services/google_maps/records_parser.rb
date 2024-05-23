# frozen_string_literal: true

require 'redis_client'
class GoogleMaps::RecordsParser
  attr_reader :import

  def initialize(import)
    @import = import
  end

  def call(json)
    data = parse_json(json)

    Point.create(
      latitude: data[:latitude],
      longitude: data[:longitude],
      timestamp: data[:timestamp],
      raw_data: data[:raw_data],
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: import.id
    )
  end

  private

  def parse_json(json)
    {
      latitude: json['latitudeE7'].to_f / 10**7,
      longitude: json['longitudeE7'].to_f / 10**7,
      timestamp: DateTime.parse(json['timestamp']).to_i,
      raw_data: json
    }
  end
end

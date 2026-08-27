# frozen_string_literal: true

class Points::GeojsonSerializer
  def initialize(points)
    @points = points
  end

  def call
    # The point serializer reads the device combo through each point's
    # source; preloading keeps that one query per collection.
    collection = points.respond_to?(:preload) ? points.preload(:source) : points

    {
      type: 'FeatureCollection',
      features: collection.map do |point|
        {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: [point.lon, point.lat]
          },
          properties: PointSerializer.new(point).call
        }
      end
    }.to_json
  end
  # rubocop:enable Metrics/MethodLength

  private

  attr_reader :points
end

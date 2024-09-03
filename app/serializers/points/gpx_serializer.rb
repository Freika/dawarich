# frozen_string_literal: true

class Points::GpxSerializer
  def initialize(points)
    @points = points
  end

  def call
    geojson_data = Points::GeojsonSerializer.new(points).call

    GPX::GeoJSON.convert_to_gpx(geojson_data:)
  end

  private

  attr_reader :points
end

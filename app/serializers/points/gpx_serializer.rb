# frozen_string_literal: true

class Points::GpxSerializer
  def initialize(points)
    @points = points
  end

  def call
    gpx = GPX::GPXFile.new

    points.each do |point|
      gpx.waypoints << GPX::Waypoint.new(
        lat: point.latitude.to_f,
        lon: point.longitude.to_f,
        time: point.recorded_at.strftime('%FT%R:%SZ'),
        ele: point.altitude.to_f
      )
    end

    gpx
  end

  private

  attr_reader :points
end

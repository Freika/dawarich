# frozen_string_literal: true

class Points::GpxSerializer
  def initialize(points, name)
    @points = points
    @name = name
  end

  def call
    gpx_file = GPX::GPXFile.new(name: "dawarich_#{name}")
    track = GPX::Track.new(name: "dawarich_#{name}")

    gpx_file.tracks << track

    track_segment = GPX::Segment.new
    track.segments << track_segment

    points.each do |point|
      track_segment.points << GPX::TrackPoint.new(
        lat: point.latitude.to_f,
        lon: point.longitude.to_f,
        elevation: point.altitude.to_f,
        time: point.recorded_at
      )
    end

    GPX::GPXFile.new(
      name: "dawarich_#{name}",
      gpx_data: gpx_file.to_s.sub('<gpx', '<gpx xmlns="http://www.topografix.com/GPX/1/1"')
    )
  end

  private

  attr_reader :points, :name
end

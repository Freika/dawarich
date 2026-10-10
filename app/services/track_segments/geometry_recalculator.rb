# frozen_string_literal: true

class TrackSegments::GeometryRecalculator
  def self.call(track, points)
    new(track, points).call
  end

  def self.apply(segment, points)
    new(segment.track, points).apply(segment)
  end

  def self.distance(points)
    points.each_cons(2).sum { |first, second| distance_between(first, second) }
  end

  def self.distance_between(first, second)
    Geocoder::Calculations.distance_between(
      [first.lat, first.lon], [second.lat, second.lon], units: :km
    ) * 1000
  end

  def initialize(track, points)
    @track = track
    @points = points
  end

  def call
    track.track_segments.order(:id).each { |segment| apply(segment) }
  end

  def apply(segment)
    update(segment, points_for(segment))
    segment
  end

  private

  attr_reader :track, :points

  def points_for(segment)
    if segment.start_at && segment.end_at
      points.select { |point| point.timestamp.between?(segment.start_at.to_i, segment.end_at.to_i) }
    else
      points.slice(segment.start_index.to_i..segment.end_index.to_i) || []
    end
  end

  def update(segment, segment_points)
    segment_distance = self.class.distance(segment_points).round
    duration = segment_duration(segment, segment_points)
    speeds = pair_speeds(segment_points)

    segment.assign_attributes(
      path: segment_points.size >= 2 ? build_path(segment_points) : nil,
      distance: segment_distance,
      duration: duration,
      avg_speed: Track.avg_speed_kmh(segment_distance, duration),
      max_speed: speeds.max || 0.0
    )
    segment.save! if segment.changed?
  end

  def segment_duration(segment, segment_points)
    return segment.end_at.to_i - segment.start_at.to_i if segment.start_at && segment.end_at
    return 0 if segment_points.size < 2

    segment_points.last.timestamp - segment_points.first.timestamp
  end

  def pair_speeds(segment_points)
    segment_points.each_cons(2).filter_map do |first, second|
      seconds = second.timestamp - first.timestamp
      next unless seconds.positive?

      (self.class.distance_between(first, second) / seconds) * 3.6
    end
  end

  def build_path(segment_points)
    factory.line_string(
      segment_points.map { |point| factory.point(point.lon.round(5), point.lat.round(5)) }
    )
  end

  def factory
    @factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
  end
end

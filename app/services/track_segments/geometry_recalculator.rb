# frozen_string_literal: true

class TrackSegments::GeometryRecalculator
  EARTH_RADIUS_METERS = 6_371_008.8

  def self.call(track, points)
    new(track, points).call
  end

  def self.distance(points)
    points.each_cons(2).sum { |first, second| distance_between(first, second) }
  end

  def self.distance_between(first, second)
    lat1 = radians(first.lat)
    lat2 = radians(second.lat)
    delta_lat = lat2 - lat1
    delta_lon = radians(second.lon - first.lon)
    haversine = Math.sin(delta_lat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(delta_lon / 2)**2

    2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt([haversine, 1.0].min))
  end

  def self.radians(degrees)
    degrees.to_f * Math::PI / 180
  end
  private_class_method :radians

  def initialize(track, points)
    @track = track
    @points = points
  end

  def call
    track.track_segments.order(:id).each do |segment|
      segment_points = points_for(segment)
      update(segment, segment_points)
    end
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

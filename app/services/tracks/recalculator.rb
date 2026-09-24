# frozen_string_literal: true

class Tracks::Recalculator
  SnapshotPoint = Data.define(:id, :timestamp, :lon, :lat, :altitude)

  def self.call(track, broadcast: true)
    new(track, broadcast:).call
  end

  def initialize(track, broadcast: true)
    @track = track
    @broadcast = broadcast
  end

  def call
    points = snapshot
    raise ActiveRecord::RecordInvalid, track if points.size < 2

    track.instance_variable_set(:@recalculated_point_count, points.size)

    track.assign_attributes(
      original_path: build_path(points),
      distance: distance(points),
      duration: points.last.timestamp - points.first.timestamp
    )
    track.avg_speed = Track.avg_speed_kmh(track.distance, track.duration)
    track.suppress_next_update_broadcast! unless broadcast
    track.save!

    TrackSegments::GeometryRecalculator.call(track, points)
    track
  end

  private

  attr_reader :track, :broadcast

  def snapshot
    altitude = if Point.connection.column_exists?(:points, :altitude_decimal)
                 'COALESCE(altitude_decimal, altitude)'
               else
                 'altitude'
               end
    sql = Point.sanitize_sql_array([<<~SQL.squish, track.id])
      SELECT id, timestamp,
             ST_X(lonlat::geometry) AS longitude,
             ST_Y(lonlat::geometry) AS latitude,
             #{altitude} AS altitude
      FROM points
      WHERE track_id = ? AND anomaly IS NOT TRUE
      ORDER BY timestamp ASC, id ASC
    SQL

    Point.connection.select_all(sql).map do |row|
      SnapshotPoint.new(
        id: row['id'].to_i,
        timestamp: row['timestamp'].to_i,
        lon: row['longitude'].to_f,
        lat: row['latitude'].to_f,
        altitude: row['altitude']&.to_f
      )
    end
  end

  def build_path(points)
    coordinates = points.map { |point| factory.point(point.lon.round(5), point.lat.round(5)) }
    factory.line_string(coordinates)
  end

  def distance(points)
    TrackSegments::GeometryRecalculator.distance(points).round
  end

  def factory
    @factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
  end
end

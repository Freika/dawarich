# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'Trip route tile performance', :eval do
  def tile_for(longitude, latitude, zoom)
    n = 2**zoom
    lat = latitude * Math::PI / 180
    [((longitude + 180) / 360 * n).floor,
     ((1 - (Math.log(Math.tan(lat) + (1 / Math.cos(lat))) / Math::PI)) / 2 * n).floor]
  end

  it 'builds tiles of a dense 300-day trip within two seconds at every zoom' do
    user = create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 30 })
    start = Time.utc(2025, 1, 1)
    trip = create(:trip, user:, started_at: start, ended_at: start + 300.days, path: nil,
                         skip_calculation_enqueue: true)
    connection = ActiveRecord::Base.connection

    connection.execute(<<~SQL.squish)
      INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, duration, created_at, updated_at)
      SELECT #{user.id}, 'phone', to_timestamp(t0) AT TIME ZONE 'UTC', to_timestamp(t0 + 1799) AT TIME ZONE 'UTC',
        ST_SetSRID(ST_MakeLine(ST_MakePoint(-140 + (k % 30) * 0.01, -40 + (k / 30) * 0.005),
                               ST_MakePoint(-140 + (k % 30) * 0.01 + 0.09, -40 + (k / 30) * 0.005)), 4326),
        0, 1800, now(), now()
      FROM (SELECT k, #{start.to_i} + (k / 2) * 86400 + CASE WHEN k % 2 = 0 THEN 36000 ELSE 85500 END AS t0
            FROM generate_series(0, 599) AS k) AS starts
    SQL
    connection.execute(<<~SQL.squish)
      INSERT INTO points (user_id, track_id, tracker_id, timestamp, lonlat, created_at, updated_at)
      SELECT tracks.user_id, tracks.id, 'phone', EXTRACT(EPOCH FROM tracks.start_at)::bigint + second,
        ST_SetSRID(ST_MakePoint(ST_X(ST_StartPoint(tracks.original_path)) + (second * 0.00005),
                                ST_Y(ST_StartPoint(tracks.original_path))), 4326)::geography,
        now(), now()
      FROM tracks CROSS JOIN generate_series(0, 1799) AS second
      WHERE tracks.user_id = #{user.id}
    SQL
    connection.execute('ANALYZE points; ANALYZE tracks')
    expect(Point.where(user:).count).to eq(1_080_000)

    trip = Trip.find(trip.id)
    windows_seconds = Benchmark.realtime { trip.multiple_recording_devices? }
    puts "recording devices (cold): #{windows_seconds.round(2)}s"

    timings = [5, 8, 11, 14].to_h do |zoom|
      x, y = tile_for(-139.9, -39.95, zoom)
      query = Trips::RoutesTileQuery.new(trip:, z: zoom, x:, y:, timezone: 'UTC',
                                         points_scope: trip.primary_device_points)
      result = nil
      seconds = Benchmark.realtime { result = query.call }
      puts "z#{zoom}: #{seconds.round(2)}s, #{result.feature_count} features"
      [zoom, seconds]
    end

    expect(timings.values).to all(be < 2.0)
  end

  it 'builds tiles of a trip whose points have no tracks yet within two seconds' do
    user = create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 30 })
    start = Time.utc(2025, 1, 1)
    trip = create(:trip, user:, started_at: start, ended_at: start + 300.days, path: nil,
                         skip_calculation_enqueue: true)
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO points (user_id, tracker_id, timestamp, lonlat, created_at, updated_at)
      SELECT #{user.id}, 'phone', #{start.to_i} + (s / 80) * 86400 + 36000 + (s % 80) * 20,
        ST_SetSRID(ST_MakePoint(-140 + (s % 80) * 0.001, -40 + (s / 80) * 0.0001), 4326)::geography, now(), now()
      FROM generate_series(0, 39999) AS s
    SQL
    ActiveRecord::Base.connection.execute('ANALYZE points')

    trip = Trip.find(trip.id)
    timings = [5, 11, 14].to_h do |zoom|
      x, y = tile_for(-139.97, -39.98, zoom)
      query = Trips::RoutesTileQuery.new(trip:, z: zoom, x:, y:, timezone: 'UTC',
                                         points_scope: trip.primary_device_points)
      result = nil
      seconds = Benchmark.realtime { result = query.call }
      puts "untracked z#{zoom}: #{seconds.round(2)}s, #{result.feature_count} features"
      [zoom, seconds]
    end

    expect(timings.values).to all(be < 2.0)
  end
end

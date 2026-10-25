# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polar routes follow the great circle' do
  it 'renders a sparse polar track through its spherical midpoint instead of along a latitude parallel' do
    track = create(:track, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :flying)
    rows = Tracks::VectorTileQuery.new(scope: Track.where(id: track.id), z: 0, x: 0, y: 0).feature_rows
    expect(rows.map { |row| row['id'].to_i }).to eq([track.id])

    radians = Math::PI / 180
    midpoint_longitude = 90.0
    midpoint_latitude = Math.atan(Math.tan(82 * radians) / Math.cos(50 * radians))
    midpoint_x = (midpoint_longitude + 180) / 360 * Tracks::VectorTileQuery::EXTENT
    midpoint_y = (1 - Math.log(Math.tan(Math::PI / 4 + midpoint_latitude / 2)) / Math::PI) / 2 *
                 Tracks::VectorTileQuery::EXTENT
    distance_sql = Track.sanitize_sql_array(
      ['SELECT ST_Distance(?::geometry, ST_SetSRID(ST_MakePoint(?, ?), 3857))',
       rows.first.fetch('geom'), midpoint_x, midpoint_y]
    )
    midpoint_error = ActiveRecord::Base.connection.select_value(distance_sql).to_f

    expect(midpoint_error).to be < 10,
                              "Polar route misses its great-circle midpoint by #{midpoint_error.round(2)} tile units"
  end

  it 'serves a sparse polar track in the tiles its arc crosses but its chord misses' do
    track = create(:track, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :flying)

    rows = Tracks::VectorTileQuery.new(scope: Track.where(id: track.id), z: 4, x: 11, y: 0).feature_rows

    expect(rows.map { |row| row['id'].to_i }).to eq([track.id])
  end

  it 'serves a sparse polar trip route in the tiles its arc crosses but its chord misses' do
    user = create(:user, settings: { 'timezone' => 'UTC' })
    trip = create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 2), path: nil,
                         skip_calculation_enqueue: true)
    track = create(:track, user:, start_at: Time.utc(2026, 1, 1, 10), end_at: Time.utc(2026, 1, 1, 18),
                           original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :flying)

    rows = Trips::RoutesTileQuery.new(trip:, z: 4, x: 11, y: 0, timezone: 'UTC',
                                      points_scope: trip.primary_device_points).feature_rows

    expect(rows.map { |row| row['track_id'].to_i }).to eq([track.id])
  end

  it 'serves a sparse polar segment in speed tiles its arc crosses but its chord misses' do
    user = create(:user)
    start_at = Time.utc(2026, 1, 1, 10)
    track = create(:track, user:, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :flying,
                           start_at:, end_at: start_at + 8.hours)
    [[40, 0], [140, 8.hours.to_i]].each do |longitude, offset|
      create(:point, user:, track:, longitude:, latitude: 82, timestamp: start_at.to_i + offset)
    end

    rows = Tracks::SpeedVectorTileQuery.new(scope: user.tracks, points_scope: user.points, z: 8, x: 192, y: 1)
                                       .feature_rows

    expect(rows.map { |row| row['id'].to_i }.uniq).to eq([track.id])
  end

  it 'treats a fast track with an undetected mode as a flight' do
    track = create(:track, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :unknown, avg_speed: 600)

    rows = Tracks::VectorTileQuery.new(scope: Track.where(id: track.id), z: 4, x: 11, y: 0).feature_rows

    expect(rows.map { |row| row['id'].to_i }).to eq([track.id])
  end

  it 'keeps chord-only tile selection for sparse tracks that are not flights' do
    track = create(:track, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :driving, avg_speed: 60)

    rows = Tracks::VectorTileQuery.new(scope: Track.where(id: track.id), z: 4, x: 11, y: 0).feature_rows

    expect(rows).to be_empty
  end
end

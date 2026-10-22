# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::RoutesTileQuery do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 60 }) }
  let(:trip) do
    create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 3), path: nil,
                  skip_calculation_enqueue: true)
  end
  let(:zoom) { 10 }

  def tile_for(longitude, latitude, zoom)
    n = 2**zoom
    x = ((longitude + 180) / 360 * n).floor
    lat = latitude * Math::PI / 180
    y = ((1 - (Math.log(Math.tan(lat) + (1 / Math.cos(lat))) / Math::PI)) / 2 * n).floor
    [x, y]
  end

  def recorded_track(times, longitudes, tracker: 'phone')
    track = create(:track, user:, tracker_id: tracker, start_at: times.first, end_at: times.last,
                           original_path: "LINESTRING(#{longitudes.map { |lon| "#{lon} -40" }.join(', ')})")
    times.zip(longitudes).each do |time, longitude|
      create(:point, user:, track:, tracker_id: tracker, timestamp: time.to_i, lonlat: "POINT(#{longitude} -40)")
    end
    track
  end

  def features(exclude_windows: [], privacy_zones: [], points_scope: nil)
    x, y = tile_for(-140.02, -40, zoom)
    described_class.new(
      trip: Trip.find(trip.id), z: zoom, x:, y:, timezone: 'UTC',
      points_scope: points_scope || Trip.find(trip.id).primary_device_points,
      exclude_windows:, privacy_zones:
    ).feature_rows
  end

  def coordinates(row)
    geometry = JSON.parse(row['geojson'])
    geometry['type'] == 'LineString' ? geometry['coordinates'] : geometry['coordinates'].flatten(1)
  end

  def minutes_after(day, hour, minute = 0)
    Time.utc(2026, 1, day, hour, minute)
  end

  it 'returns one feature per day the trip moved' do
    recorded_track([minutes_after(1, 10), minutes_after(1, 10, 30)], [-140.0, -140.01])
    recorded_track([minutes_after(2, 10), minutes_after(2, 10, 30)], [-140.02, -140.03])

    expect(features.map { |row| row['day'] }).to contain_exactly('2026-01-01', '2026-01-02')
  end

  it 'splits a track that crosses local midnight into one feature per day' do
    times = [minutes_after(1, 23, 40), minutes_after(1, 23, 50), minutes_after(2, 0, 10), minutes_after(2, 0, 20)]
    recorded_track(times, [-140.0, -140.01, -140.02, -140.03])

    expect(features.map { |row| row['day'] }).to contain_exactly('2026-01-01', '2026-01-02')
  end

  it 'leaves out tracks of a device that is not the primary one' do
    recorded_track((0..5).map { |step| minutes_after(1, 10, step * 5) }, (0..5).map { |step| -140.0 - (step * 0.01) })
    recorded_track([minutes_after(1, 10, 1), minutes_after(1, 10, 6)], [-140.2, -140.21], tracker: 'watch')

    rows = features

    expect(rows.size).to eq(1)
    expect(coordinates(rows.first).map(&:first)).to all(be_between(-140.06, -140.0))
  end

  it "breaks a rebuilt route at the owner's route gap" do
    trip.update_columns(started_at: minutes_after(1, 10))
    times = [minutes_after(1, 9, 50), minutes_after(1, 10, 5), minutes_after(1, 10, 15),
             minutes_after(1, 12, 15), minutes_after(1, 12, 25)]
    recorded_track(times, [-140.0, -140.01, -140.02, -140.03, -140.04])

    expect(JSON.parse(features.first['geojson'])['type']).to eq('MultiLineString')

    user.update!(settings: user.settings.merge('minutes_between_routes' => 240))
    expect(JSON.parse(features.first['geojson'])['type']).to eq('LineString')
  end

  it 'cuts a track that starts before the trip' do
    trip.update_columns(started_at: minutes_after(1, 10))
    times = [minutes_after(1, 9, 40), minutes_after(1, 9, 50), minutes_after(1, 10, 5), minutes_after(1, 10, 15)]
    recorded_track(times, [-140.0, -140.01, -140.02, -140.03])

    rows = features

    expect(rows.map { |row| row['day'] }).to eq(['2026-01-01'])
    expect(rows.first['start_timestamp'].to_i).to be >= trip.started_at.to_i
  end

  it 'splits the route around an excluded window' do
    times = (0..4).map { |step| minutes_after(1, 10, step * 5) }
    recorded_track(times, [-140.0, -140.01, -140.02, -140.03, -140.04])

    rows = features(exclude_windows: [[times[2].to_i - 1, times[2].to_i + 1]])

    expect(rows.size).to eq(1)
    expect(JSON.parse(rows.first['geojson'])['type']).to eq('MultiLineString')
    expect(coordinates(rows.first).map(&:first)).not_to include(-140.02)
  end

  it 'never draws within a privacy zone, even between points on both sides of it' do
    times = (0..3).map { |step| minutes_after(1, 10, step * 5) }
    recorded_track(times, [-140.0, -140.01, -140.03, -140.04])
    zone = { lon: -140.02, lat: -40.0, radius: 500 }

    rows = features(privacy_zones: [zone])

    distance_sql = 'SELECT ST_Distance(ST_GeomFromGeoJSON(?)::geography, ST_MakePoint(-140.02, -40)::geography)'
    distances = rows.map do |row|
      ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([distance_sql, row['geojson']]))
                        .to_f
    end
    expect(distances).not_to be_empty
    expect(distances).to all(be >= 499)
  end

  it 'draws points that belong to no track' do
    [minutes_after(1, 9), minutes_after(1, 9, 10)].zip([-140.0, -140.01]).each do |time, longitude|
      create(:point, user:, track: nil, timestamp: time.to_i, lonlat: "POINT(#{longitude} -40)")
    end

    expect(features.map { |row| row['day'] }).to eq(['2026-01-01'])
  end

  it 'follows untracked points that leave the tile instead of cutting across' do
    [[minutes_after(1, 9), -140.02], [minutes_after(1, 9, 10), -142.0], [minutes_after(1, 9, 20), -140.03]]
      .each do |time, longitude|
        create(:point, user:, track: nil, timestamp: time.to_i, lonlat: "POINT(#{longitude} -40)")
      end

    longitudes = features.flat_map { |row| coordinates(row).map(&:first) }

    expect(longitudes).to include(-142.0)
  end

  it 'leaves out tracks before a Lite plan data window' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)
    trip.update_columns(started_at: 2.years.ago, ended_at: 2.years.ago + 2.days)
    old_start = 2.years.ago + 1.hour
    recorded_track([old_start, old_start + 30.minutes], [-140.0, -140.01])

    rows = features(points_scope: Trip.find(trip.id).primary_device_points.merge(user.scoped_points))

    expect(rows).to be_empty
  end

  it 'rejects tile coordinates outside the zoom range' do
    query = described_class.new(trip:, z: 2, x: 9, y: 0, timezone: 'UTC', points_scope: trip.primary_device_points)

    expect { query.feature_rows }.to raise_error(described_class::InvalidTileCoordinatesError)
  end
end

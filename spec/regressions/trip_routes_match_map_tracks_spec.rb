# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip routes draw the same tracks as the map' do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 30 }) }

  # Made-up coordinates in the open ocean, unrelated to any real recording.
  def recorded_track(times, longitudes)
    track = create(:track, user:, tracker_id: 'synthetic-phone', start_at: times.first, end_at: times.last,
                           original_path: "LINESTRING(#{longitudes.map { |lon| "#{lon} -40" }.join(', ')})")
    times.zip(longitudes).each do |time, longitude|
      create(:point, user:, track:, tracker_id: 'synthetic-phone', timestamp: time.to_i,
                     lonlat: "POINT(#{longitude} -40)")
    end
    track
  end

  def trip_between(started_at, ended_at)
    create(:trip, user:, started_at:, ended_at:, path: nil, skip_calculation_enqueue: true)
  end

  # z10/x113/y636 holds every synthetic coordinate below, away from tile edges.
  def trip_route_rows(trip)
    Trips::RoutesTileQuery.new(trip:, z: 10, x: 113, y: 636, timezone: 'UTC',
                               points_scope: trip.primary_device_points).feature_rows
  end

  # The map draws a track cut to a time window from all of its points in that window.
  def map_track_path(track, trip)
    Tracks::PointGeometryQuery.new(points_scope: user.points, start_at: trip.started_at, end_at: trip.ended_at)
                              .path_sql(track_id_sql: track.id)
  end

  def covered_by_trip_routes?(rows, track, trip)
    geometries = rows.map { |row| "ST_GeomFromGeoJSON(#{ActiveRecord::Base.connection.quote(row['geojson'])})" }
    return false if geometries.empty?

    ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT ST_Covers(ST_Collect(ARRAY[#{geometries.join(', ')}]), map_track.path)
      FROM (#{map_track_path(track, trip)}) AS map_track
    SQL
  end

  it 'keeps the segment of a track that crosses local midnight' do
    started_at = Time.utc(2026, 1, 1, 23, 55)
    ended_at = Time.utc(2026, 1, 2, 0, 5)
    track = recorded_track([started_at, ended_at], [-140.02, -140.01])
    trip = trip_between(started_at, ended_at)

    rows = trip_route_rows(trip)

    expect(rows).not_to be_empty
    expect(covered_by_trip_routes?(rows, track, trip)).to be(true)
  end

  it 'keeps a pause inside a track that is longer than the gap between routes' do
    times = [Time.utc(2026, 1, 1, 22), Time.utc(2026, 1, 1, 22, 10), Time.utc(2026, 1, 1, 23, 30),
             Time.utc(2026, 1, 2, 0, 30), Time.utc(2026, 1, 2, 0, 40)]
    track = recorded_track(times, [-140.0, -140.01, -140.02, -140.03, -140.04])
    trip = trip_between(Time.utc(2026, 1, 1, 21), Time.utc(2026, 1, 2, 1))

    expect(covered_by_trip_routes?(trip_route_rows(trip), track, trip)).to be(true)
  end

  it 'still colours each day of a track that crosses midnight on its own' do
    times = [Time.utc(2026, 1, 1, 23, 40), Time.utc(2026, 1, 1, 23, 50), Time.utc(2026, 1, 2, 0, 10),
             Time.utc(2026, 1, 2, 0, 20)]
    recorded_track(times, [-140.0, -140.01, -140.02, -140.03])
    trip = trip_between(times.first, times.last)

    expect(trip_route_rows(trip).map { |row| row['day'] }).to contain_exactly('2026-01-01', '2026-01-02')
  end

  describe 'trip preview', type: :request do
    it 'serves the line, not an empty tile, when its only segment crosses midnight' do
      started_at = Time.utc(2026, 1, 1, 23, 55)
      ended_at = Time.utc(2026, 1, 2, 0, 5)
      recorded_track([started_at, ended_at], [-140.02, -140.01])
      trip = trip_between(started_at, ended_at)
      trip.recalculate_path_and_distance!
      sign_in user

      get trips_path
      preview = Nokogiri::HTML(response.body).at_css("#map-#{trip.id}")
      tile_url = preview['data-trip-maplibre-preview-tiles-url-value']
                 .sub('{z}', '10').sub('{x}', '113').sub('{y}', '636')
      get tile_url, headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to include('trip_routes'.b)
    end
  end
end

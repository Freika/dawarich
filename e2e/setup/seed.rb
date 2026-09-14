# frozen_string_literal: true

require 'fileutils'

module TileOnlyMapE2ESeed
  module_function

  PASSWORD = 'tile-only-map-e2e-password'
  EDIT_EMAIL = 'tile-only-map-editing-e2e@example.invalid'
  LARGE_EMAIL = 'tile-only-map-large-e2e@example.invalid'
  LARGE_POINT_COUNT = Integer(ENV.fetch('E2E_LARGE_POINT_COUNT', 1_000_000))

  def call
    cleanup
    edit_user, identifiers = create_edit_fixture
    large_user = create_large_fixture
    write_manifest(edit_user, large_user, identifiers)
    puts "Seeded tile-only E2E users (large_points=#{LARGE_POINT_COUNT})"
  end

  def cleanup
    users = User.unscoped.where(email: [EDIT_EMAIL, LARGE_EMAIL])
    user_ids = users.pluck(:id)
    return if user_ids.empty?

    track_ids = Track.where(user_id: user_ids).pluck(:id)
    SharedLink.where(user_id: user_ids).delete_all
    Trip.where(user_id: user_ids).delete_all
    TrackSegment.where(track_id: track_ids).delete_all
    Point.where(user_id: user_ids).delete_all
    Track.where(id: track_ids).delete_all
    Import.where(user_id: user_ids).delete_all
    users.destroy_all
  end

  def user(email, layers)
    record = User.unscoped.find_or_initialize_by(email: email)
    record.assign_attributes(
      deleted_at: nil,
      password: PASSWORD,
      password_confirmation: PASSWORD,
      status: :active,
      active_until: 100.years.from_now,
      plan: :pro,
      settings: {
        'onboarding_completed' => true,
        'enabled_map_layers' => layers,
        'point_dragging_enabled' => true,
        'maps_maplibre_style' => 'light',
        'maps_maplibre_tiles_url' => '/e2e/basemap/{z}/{x}/{y}.mvt',
        'maps_maplibre_tiles_fallback' => false,
        'globe_projection' => false,
        'live_map_enabled' => false,
        'fog_of_war_mode' => 'points'
      }
    )
    record.save!
    record
  end

  def create_edit_fixture
    user = user(EDIT_EMAIL, ['Points', 'Tracks', 'Heatmap', 'Fog of War', 'Scratch map'])
    timestamp = Time.zone.today.noon.to_i
    track = Track.create!(
      user: user,
      start_at: Time.zone.at(timestamp),
      end_at: Time.zone.at(timestamp + 120),
      original_path: 'LINESTRING(0 0, 0.01 0.01, 0.02 0.02)',
      distance: 2_600,
      duration: 120,
      avg_speed: 78
    )
    track_points = [
      create_point(user, timestamp, 0, 0, track: track),
      create_point(user, timestamp + 60, 0.01, 0.01, track: track),
      create_point(user, timestamp + 120, 0.02, 0.02, track: track)
    ]
    import = user.imports.new(name: 'tile-only-map-e2e.geojson', source: :geojson, status: :completed)
    import.skip_background_processing = true
    import.save!
    Point.where(id: track_points.map(&:id)).update_all(import_id: import.id)
    segment = TrackSegment.create!(
      track: track,
      start_index: 0,
      end_index: 2,
      transportation_mode: :driving,
      confidence: :high,
      source: 'e2e',
      distance: 2_600,
      duration: 120,
      path: track.original_path
    )

    germany = country('DEU', 'Germany', 'DE', 'MULTIPOLYGON (((12 51, 15 51, 15 54, 12 54, 12 51)))')
    country('FRA', 'France', 'FR', 'MULTIPOLYGON (((1 47, 5 47, 5 51, 1 51, 1 47)))')
    country_point = create_point(user, timestamp + 180, 13.5, 52.5)
    country_point.update_columns(
      country_id: germany.id,
      country_name: germany.name,
      country: germany.name
    )
    trip = Trip.create!(
      user: user,
      name: 'Tile-only preservation trip',
      started_at: Time.zone.at(timestamp),
      ended_at: Time.zone.at(timestamp + 120),
      path: 'LINESTRING(0 0, 0.01 0.01, 0.02 0.02)',
      distance: 2_600,
      demo: true
    )
    shared_trip = SharedLink.create!(
      user: user,
      resource_type: :trip,
      resource_id: trip.id,
      name: 'Tile-only preservation trip',
      settings: {
        'show_route' => true,
        'show_days' => true,
        'show_photos' => false,
        'show_stats' => true
      }
    )
    user.update_column(:points_count, 4)

    [
      user,
      {
        track_id: track.id,
        import_id: import.id,
        track_point_ids: track_points.map(&:id),
        segment_id: segment.id,
        country_point_id: country_point.id,
        country_point_revision: country_point.lock_version,
        trip_id: trip.id,
        shared_trip_id: shared_trip.id,
        history_scope: {
          start_at: Time.zone.today.beginning_of_day.iso8601,
          end_at: Time.zone.today.end_of_day.iso8601
        }
      }
    ]
  end

  def create_large_fixture
    user = user(LARGE_EMAIL, ['Points', 'Heatmap', 'Fog of War'])
    start_timestamp = 5.years.ago.beginning_of_day.to_i
    span = 5.years.to_i
    now = Time.current
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      INSERT INTO points (
        user_id, timestamp, lonlat, geodata, motion_data, raw_data,
        raw_data_archived, in_regions, inrids, anomaly, lock_version,
        created_at, updated_at
      )
      SELECT
        #{user.id},
        #{start_timestamp} + (series % #{span}),
        ST_SetSRID(
          ST_MakePoint(
            -170 + ((series % 340000)::numeric / 1000),
            -70 + ((series % 140000)::numeric / 1000)
          ), 4326
        )::geography,
        '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
        FALSE, ARRAY[]::text[], ARRAY[]::text[], FALSE, 0,
        #{connection.quote(now)}, #{connection.quote(now)}
      FROM generate_series(1, #{LARGE_POINT_COUNT}) AS series
    SQL
    user.update_column(:points_count, LARGE_POINT_COUNT)
    user
  end

  def create_point(user, timestamp, longitude, latitude, track: nil)
    Point.create!(
      user: user,
      track: track,
      timestamp: timestamp,
      lonlat: "POINT(#{longitude} #{latitude})",
      geodata: {},
      motion_data: {},
      raw_data: {}
    )
  end

  def country(iso_a3, name, iso_a2, geometry)
    Country.find_or_create_by!(iso_a3: iso_a3) do |record|
      record.name = name
      record.iso_a2 = iso_a2
      record.geom = geometry
    end
  end

  def write_manifest(edit_user, large_user, identifiers)
    directory = Rails.root.join('e2e/temp')
    FileUtils.mkdir_p(directory)
    File.write(
      directory.join('seed.json'),
      JSON.pretty_generate(
        identifiers.merge(
          edit_email: EDIT_EMAIL,
          large_email: LARGE_EMAIL,
          password: PASSWORD,
          edit_api_key: edit_user.api_key,
          large_api_key: large_user.api_key,
          large_point_count: LARGE_POINT_COUNT,
          large_history_scope: {
            start_at: 5.years.ago.beginning_of_day.iso8601,
            end_at: Time.zone.now.end_of_day.iso8601
          }
        )
      )
    )
  end
end

TileOnlyMapE2ESeed.call unless ENV['E2E_SEED_SKIP_CALL'] == 'true'

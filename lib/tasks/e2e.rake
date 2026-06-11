# frozen_string_literal: true

# Tasks for resetting + seeding the canonical state expected by the
# e2e-dawarich-playwright suite.
#
# The Playwright specs assume:
#   - demo@dawarich.app: ~1000 points (Berlin), 50+50 visits, 10 areas,
#     20 tracks, timeline fixtures, family — all dated around 2025-10-15
#   - lite@dawarich.app: 20 points within 12mo + 10 points 13-14mo old,
#     so the "data window" upsell banner appears
#
# Run via:
#   bin/rails e2e:reset_and_seed
#   # or
#   bin/seed_e2e

namespace :e2e do
  E2E_USER_EMAILS = %w[
    demo@dawarich.app
    lite@dawarich.app
    family.member1@dawarich.app
    family.member2@dawarich.app
    family.member3@dawarich.app
  ].freeze

  # The base time the demo data is shifted to land at. Specs hardcode
  # 2025-10-15 in URL params (see e2e-dawarich-playwright/v2/map/...);
  # keep this aligned.
  E2E_BASE_TIME_STR = '2025-10-15 23:59:00'

  # Deterministic anomaly fixtures for regression specs around
  # #2474 (Trip anomaly filter), #2476 (Select Area includes anomalies),
  # #2630 (bulk track recalc excludes anomalies). Keep in sync with
  # e2e-dawarich-playwright/v2/helpers/anomaly.js.
  E2E_ANOMALY_FIXTURE = [
    { lat: 52.5200, lon: 13.4050, hour: 12.0, country: 'Germany' },
    { lat: 52.5210, lon: 13.4060, hour: 12.5, country: 'Germany' },
    { lat: 52.5190, lon: 13.4070, hour: 13.0, country: 'Germany' },
    { lat: 48.8500, lon: 2.3500,  hour: 14.0, country: 'France' },
    { lat: 52.6000, lon: 13.5000, hour: 15.0, country: 'Germany' }
  ].freeze

  E2E_ANOMALY_TRIP_NAME = 'E2E Anomaly Day'.freeze
  E2E_ANOMALY_TRIP_START = '2025-10-15 11:00:00'.freeze
  E2E_ANOMALY_TRIP_END   = '2025-10-15 18:00:00'.freeze

  # Tag fixtures for timeline-filters spec "Tag chips" describe. Three tags
  # plus one "tag-holder" place that carries all three — so the e2e suite
  # can look up tag IDs via /api/v1/places (which exposes place.tags),
  # avoiding the need for a separate tags-index API endpoint.
  E2E_TAG_NAMES = %w[e2e-Home e2e-Work e2e-Travel].freeze
  E2E_TAG_HOLDER_PLACE_NAME = 'E2E Tag Holder'.freeze

  # Fixed Track windows used by the timeline-replay and timeline-journey-leg
  # specs. These live deep in the past so they don't collide with other
  # fixtures or the demo data (which clusters around 2025-10-15).
  E2E_REPLAY_TRACK_DAY     = '2020-10-03'.freeze
  E2E_REPLAY_TRACK_START   = '2020-10-03 09:30:00 UTC'.freeze
  E2E_REPLAY_TRACK_END     = '2020-10-03 10:30:00 UTC'.freeze
  E2E_JOURNEY_TRACK_DAY    = '2020-06-06'.freeze
  E2E_JOURNEY_TRACK_START  = '2020-06-06 09:00:00 UTC'.freeze
  E2E_JOURNEY_TRACK_END    = '2020-06-06 10:00:00 UTC'.freeze

  # Normal (non-anomaly) Berlin points that sit inside the anomaly trip
  # window. Demo data has many points but most carry country_name=nil, so
  # without these the trip's calculate_countries returns []. These are the
  # Germany baseline that the trip spec asserts against.
  E2E_TRIP_BACKBONE_FIXTURE = [
    { lat: 52.5170, lon: 13.3880, hour: 11.5, country: 'Germany' },
    { lat: 52.5180, lon: 13.3900, hour: 12.25, country: 'Germany' },
    { lat: 52.5160, lon: 13.3950, hour: 13.5, country: 'Germany' },
    { lat: 52.5140, lon: 13.4000, hour: 16.0, country: 'Germany' }
  ].freeze

  def assert_safe_environment!
    return unless Rails.env.production?
    return if ENV['ALLOW_E2E_RESET'] == '1'

    abort '✋ Refusing to run e2e:reset in production. Set ALLOW_E2E_RESET=1 to override.'
  end

  desc 'Reset demo + lite + family users to a clean state and re-seed canonical e2e data'
  task reset_and_seed: :environment do
    assert_safe_environment!

    puts '🧹 Resetting e2e users...'
    Rake::Task['e2e:reset'].invoke

    base_time = Time.zone.parse(E2E_BASE_TIME_STR)
    geojson_path = Rails.root.join('tmp/demo_data_e2e.geojson').to_s
    puts "\n📝 Generating GeoJSON at #{geojson_path} (base_time=#{base_time.iso8601})..."
    geojson = DemoData::GeojsonGenerator.new(base_time: base_time).call
    File.write(geojson_path, geojson)
    puts "✅ Wrote #{File.size(geojson_path)} bytes"

    puts "\n🚀 Invoking demo:seed_data..."
    Rake::Task['demo:seed_data'].invoke(geojson_path)

    # The import enqueues track generation / geocoding / stats jobs. Those
    # rebuild tracks, which nullifies any track_id assigned below (the #2630
    # polluter) — wait for the churn to settle before planting fixtures.
    puts "\n⏳ Waiting for background jobs to settle..."
    require 'sidekiq/api'
    deadline = Time.current + 5.minutes
    loop do
      busy = Sidekiq::Workers.new.size
      enqueued = Sidekiq::Queue.all.sum(&:size)
      break if busy.zero? && enqueued.zero?

      if Time.current > deadline
        puts "  ↪ still busy after 5 minutes (busy=#{busy} enqueued=#{enqueued}) — continuing anyway"
        break
      end
      sleep 2
    end

    puts "\n⚠️  Planting anomaly fixtures..."
    Rake::Task['e2e:seed_anomalies'].invoke

    puts "\n🧭 Seeding the anomaly-window demo trip..."
    Rake::Task['e2e:seed_demo_trip'].invoke

    puts "\n🏷️  Seeding tag fixtures..."
    Rake::Task['e2e:seed_tag_fixtures'].invoke

    puts "\n🛤️  Seeding fixture tracks (timeline-replay + journey-leg specs)..."
    Rake::Task['e2e:seed_fixture_tracks'].invoke

    puts "\n🔕 Suppressing the changelog prompt + onboarding modal for e2e users..."
    User.where(email: E2E_USER_EMAILS).find_each do |user|
      user.update_columns(
        changelog_consent: User.changelog_consents[:declined],
        settings: (user.settings || {}).merge('onboarding_completed' => true)
      )
    end
  end

  desc 'Plant a deterministic set of anomaly points on the demo user (idempotent).'
  task seed_anomalies: :environment do
    assert_safe_environment!

    user = User.find_by!(email: 'demo@dawarich.app')
    base_day = Time.zone.parse('2025-10-15')

    user.points.where(tracker_id: ['e2e-anomaly', 'e2e-backbone']).delete_all

    E2E_TRIP_BACKBONE_FIXTURE.each do |row|
      ts = (base_day + (row[:hour] * 3600).to_i.seconds).to_i

      next if user.points.exists?(timestamp: ts, lonlat: "POINT(#{row[:lon]} #{row[:lat]})")

      user.points.create!(
        lonlat: "POINT(#{row[:lon]} #{row[:lat]})",
        timestamp: ts,
        anomaly: false,
        tracker_id: 'e2e-backbone',
        country_name: row[:country]
      )
    end

    E2E_ANOMALY_FIXTURE.each do |row|
      ts = (base_day + (row[:hour] * 3600).to_i.seconds).to_i

      next if user.points.exists?(timestamp: ts, lonlat: "POINT(#{row[:lon]} #{row[:lat]})")

      user.points.create!(
        lonlat: "POINT(#{row[:lon]} #{row[:lat]})",
        timestamp: ts,
        anomaly: true,
        tracker_id: 'e2e-anomaly',
        country_name: row[:country]
      )
    end

    count = user.points.where(tracker_id: 'e2e-anomaly').count
    puts "  ↪ planted #{count} anomaly points (#{count == E2E_ANOMALY_FIXTURE.size ? 'ok' : 'MISMATCH'})"

    # The #2630 polluter lives OUTSIDE the shared anomaly bbox (and under its
    # own tracker_id) so the destructive area-selection specs that delete the
    # ANOMALY_COORDS cluster never consume it mid-run. Keep in sync with
    # POLLUTER_COORD in e2e-dawarich-playwright/v2/helpers/anomaly.js.
    user.points.where(tracker_id: 'e2e-anomaly-polluter').delete_all
    polluter_ts = (base_day + (16 * 3600).seconds).to_i
    polluter = user.points.create!(
      lonlat: 'POINT(13.7 52.7)',
      timestamp: polluter_ts,
      anomaly: true,
      tracker_id: 'e2e-anomaly-polluter',
      country_name: 'Germany'
    )
    day_start = base_day.to_i
    day_end   = (base_day + 1.day).to_i
    polluter_track = user.tracks
                         .where('start_at >= ? AND start_at < ?', Time.zone.at(day_start), Time.zone.at(day_end))
                         .order(:start_at)
                         .first
    if polluter_track
      polluter.update_columns(track_id: polluter_track.id)
      puts "  ↪ assigned anomaly ##{polluter.id} to track ##{polluter_track.id} as #2630 controller-filter polluter"
    else
      puts '  ↪ no track available to host polluter anomaly (skipping #2630 controller-side check)'
    end
  end

  desc 'Create the demo trip covering the anomaly window and recalculate it synchronously.'
  task seed_demo_trip: :environment do
    assert_safe_environment!

    user = User.find_by!(email: 'demo@dawarich.app')

    user.trips.where(name: E2E_ANOMALY_TRIP_NAME).destroy_all

    trip = user.trips.create!(
      name: E2E_ANOMALY_TRIP_NAME,
      started_at: Time.zone.parse(E2E_ANOMALY_TRIP_START),
      ended_at:   Time.zone.parse(E2E_ANOMALY_TRIP_END)
    )

    trip.recalculate_path_and_distance!
    trip.calculate_countries
    trip.update!(last_recalculated_at: Time.current)

    puts "  ↪ trip ##{trip.id} \"#{trip.name}\" countries=#{trip.visited_countries.inspect}"
  end

  desc 'Seed tag fixtures (3 tags + a tag-holder place) for the timeline-filters spec.'
  task seed_tag_fixtures: :environment do
    assert_safe_environment!

    user = User.find_by!(email: 'demo@dawarich.app')

    tags = E2E_TAG_NAMES.map do |name|
      user.tags.find_or_create_by!(name: name)
    end
    puts "  ↪ tags: #{tags.map { |t| "#{t.name}(##{t.id})" }.join(', ')}"

    holder = user.places.where(name: E2E_TAG_HOLDER_PLACE_NAME).first ||
             user.places.create!(
               name: E2E_TAG_HOLDER_PLACE_NAME,
               latitude: 52.5300,
               longitude: 13.4200,
               lonlat: 'POINT(13.4200 52.5300)',
               source: 'manual'
             )
    holder.tags = tags
    holder.save!
    puts "  ↪ tag-holder place ##{holder.id} \"#{holder.name}\" has tags #{holder.reload.tags.map(&:name).inspect}"
  end

  desc 'Seed deterministic Track fixtures for timeline-replay + timeline-journey-leg specs.'
  task seed_fixture_tracks: :environment do
    assert_safe_environment!

    user = User.find_by!(email: 'demo@dawarich.app')

    _seed_fixture_track(
      user,
      tracker_id: 'e2e-replay-track',
      start_at: Time.zone.parse(E2E_REPLAY_TRACK_START),
      end_at:   Time.zone.parse(E2E_REPLAY_TRACK_END)
    )

    _seed_fixture_track(
      user,
      tracker_id: 'e2e-journey-track',
      start_at: Time.zone.parse(E2E_JOURNEY_TRACK_START),
      end_at:   Time.zone.parse(E2E_JOURNEY_TRACK_END)
    )
  end

  # Plant a strip of points walking south-east at ~5m intervals over the
  # given window, then materialise a Track row via Tracks::TrackBuilder.
  # Idempotent: removes any prior fixture (points + track) with the same
  # tracker_id before re-creating.
  def _seed_fixture_track(user, tracker_id:, start_at:, end_at:)
    user.tracks.where(tracker_id: tracker_id).destroy_all
    user.points.where(tracker_id: tracker_id).delete_all

    point_count = 15
    span_seconds = (end_at - start_at).to_i
    step_seconds = span_seconds / (point_count - 1)
    base_lat = 52.5200
    base_lon = 13.4050
    step_deg = 0.0005

    points = []
    point_count.times do |i|
      lon = base_lon + (i * step_deg)
      lat = base_lat - (i * step_deg)
      ts  = start_at.to_i + (i * step_seconds)
      points << user.points.create!(
        lonlat: "POINT(#{lon} #{lat})",
        timestamp: ts,
        tracker_id: tracker_id,
        anomaly: false
      )
    end

    distance_meters = Point.total_distance(points, :m)
    builder = Class.new do
      include Tracks::TrackBuilder
      def initialize(user); @user = user; end
      attr_reader :user
    end.new(user)
    track = builder.create_track_from_points(
      points, distance_meters, tracker_id: tracker_id
    )

    raise "Failed to create fixture track for tracker_id=#{tracker_id}" if track.nil?

    puts "  ↪ fixture track ##{track.id} tracker=#{tracker_id} #{track.start_at.iso8601}..#{track.end_at.iso8601} (#{points.size} pts, #{distance_meters.to_i}m)"
  end

  desc 'Wipe data for the e2e users (demo, lite, family members) without deleting the users themselves'
  task reset: :environment do
    assert_safe_environment!

    User.where(email: E2E_USER_EMAILS).find_each do |user|
      print "  ↪ #{user.email} ... "
      reset_user_data!(user)
      puts 'done'
    end
  end

  def reset_user_data!(user)
    # Order matters: child rows first so FK constraints don't bite.
    PlaceVisit.where(visit_id: user.visits.select(:id)).delete_all
    PlaceVisit.where(place_id: user.places.select(:id)).delete_all
    TrackSegment.where(track_id: Track.where(user_id: user.id).select(:id)).delete_all
    Track.where(user_id: user.id).delete_all
    user.points.delete_all
    user.visits.delete_all
    user.places.destroy_all
    user.areas.delete_all if user.respond_to?(:areas)
    user.imports.destroy_all
    user.exports.destroy_all
    user.trips.destroy_all if user.respond_to?(:trips)
  end
end

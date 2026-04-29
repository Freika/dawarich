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

  desc 'Reset demo + lite + family users to a clean state and re-seed canonical e2e data'
  task reset_and_seed: :environment do
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
  end

  desc 'Wipe data for the e2e users (demo, lite, family members) without deleting the users themselves'
  task reset: :environment do
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
  end
end

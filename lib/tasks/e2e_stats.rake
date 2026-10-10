# frozen_string_literal: true

namespace :e2e do
  E2E_STATS_USERS = {
    reader: 'e2e-stats@dawarich.test',
    actor: 'e2e-stats-actions@dawarich.test',
    empty: 'e2e-stats-empty@dawarich.test'
  }.freeze

  E2E_STATS_PASSWORD = 'safepassword12'

  E2E_STATS_SETTINGS = {
    'timezone' => 'Europe/Berlin',
    'maps' => { 'distance_unit' => 'km' },
    'onboarding_completed' => true
  }.freeze

  E2E_STATS_STEP_DEGREES = 0.009
  E2E_STATS_STEP_SECONDS = 600

  E2E_STATS_WALKS = [
    { start: '2023-07-14 09:00', city: 'Berlin', country: 'Germany', lat: 52.5, lon: 13.4, steps: 20 },
    { start: '2024-03-05 09:00', city: 'Berlin', country: 'Germany', lat: 52.5, lon: 13.4, steps: 10 },
    { start: '2024-03-06 09:00', city: 'Berlin', country: 'Germany', lat: 52.5, lon: 13.4, steps: 6 },
    { start: '2024-03-07 09:00', city: 'Berlin', country: 'Germany', lat: 52.5, lon: 13.4, steps: 14 },
    { start: '2024-03-20 09:00', city: 'Prague', country: 'Czechia', lat: 50.08, lon: 14.42, steps: 8 },
    { start: '2024-04-10 14:00', city: 'Berlin', country: 'Germany', lat: 52.5, lon: 13.4, steps: 12 }
  ].freeze

  E2E_STATS_UNGEOCODED_POINT = { at: '2024-04-20 12:00', lat: 55.0, lon: 3.0 }.freeze

  E2E_STATS_VISITS = [
    { name: 'Office', start: '2024-03-05 12:00', minutes: 120 },
    { name: 'Office', start: '2024-03-06 12:00', minutes: 120 },
    { name: 'Home', start: '2024-04-10 18:00', minutes: 90 }
  ].freeze

  desc 'Seed the stats and insights fixture users (idempotent).'
  task seed_stats_fixtures: :environment do
    assert_safe_environment!

    zone = ActiveSupport::TimeZone[E2E_STATS_SETTINGS['timezone']]
    months = E2E_STATS_WALKS.map { |walk| zone.parse(walk[:start]) }.map { |time| [time.year, time.month] }.uniq

    E2E_STATS_USERS.each do |role, email|
      user = e2e_stats_prepare_user(email)
      next if role == :empty

      e2e_stats_create_points(user, zone)
      e2e_stats_create_visits(user, zone)
      e2e_stats_calculate(user, months, digests: role == :reader)
      puts "  ↪ #{email}: #{user.reload.points_count} points, #{user.stats.count} stats, #{user.digests.count} digests"
    end
  end

  def e2e_stats_prepare_user(email)
    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.password = E2E_STATS_PASSWORD
      user.password_confirmation = E2E_STATS_PASSWORD
    end
    user.settings = (user.settings || {}).merge(E2E_STATS_SETTINGS)
    user.save!
    user.update_columns(
      status: User.statuses[:active],
      active_until: 1000.years.from_now,
      changelog_consent: User.changelog_consents[:declined]
    )
    reset_user_data!(user)
    user.stats.delete_all
    user.digests.delete_all
    user.update_column(:points_count, 0)
    user
  end

  def e2e_stats_create_points(user, zone)
    E2E_STATS_WALKS.each do |walk|
      start = zone.parse(walk[:start]).to_i
      (0..walk[:steps]).each do |step|
        e2e_stats_point(user, walk[:lat] + (step * E2E_STATS_STEP_DEGREES), walk[:lon],
                        start + (step * E2E_STATS_STEP_SECONDS), city: walk[:city], country: walk[:country])
      end
    end

    lone = E2E_STATS_UNGEOCODED_POINT
    e2e_stats_point(user, lone[:lat], lone[:lon], zone.parse(lone[:at]).to_i, city: nil, country: nil)
    user.update_column(:points_count, user.points.count)
  end

  def e2e_stats_point(user, lat, lon, timestamp, city:, country:)
    recorded_at = Time.zone.at(timestamp)
    user.points.create!(
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: timestamp,
      city: city,
      country_name: country,
      reverse_geocoded_at: recorded_at,
      created_at: recorded_at,
      tracker_id: 'e2e-stats',
      anomaly: false
    )
  end

  def e2e_stats_create_visits(user, zone)
    E2E_STATS_VISITS.each do |visit|
      started_at = zone.parse(visit[:start])
      user.visits.create!(
        name: visit[:name],
        started_at: started_at,
        ended_at: started_at + visit[:minutes].minutes,
        duration: visit[:minutes],
        status: :confirmed
      )
    end
  end

  def e2e_stats_calculate(user, months, digests:)
    months.each { |year, month| Stats::CalculateMonth.new(user.id, year, month).call }
    raise "stats fixture incomplete for #{user.email}" unless user.stats.count == months.size
    return unless digests

    months.each { |year, month| Users::Digests::CalculateMonth.new(user.id, year, month).call }
    months.map(&:first).uniq.each { |year| Users::Digests::CalculateYear.new(user.id, year).call }
  end
end

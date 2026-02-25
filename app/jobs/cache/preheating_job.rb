# frozen_string_literal: true

class Cache::PreheatingJob < ApplicationJob
  queue_as :cache

  def perform
    # Preheat country borders GeoJSON (global, not per-user)
    Rails.cache.write(
      'dawarich/countries_codes',
      Oj.load(File.read(Rails.root.join('lib/assets/countries.geojson'))),
      expires_in: 1.day
    )

    User.find_each do |user|
      Rails.cache.write(
        "dawarich/user_#{user.id}_years_tracked",
        user.years_tracked,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_points_geocoded_stats",
        StatsQuery.new(user).cached_points_geocoded_stats,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_countries_visited",
        user.countries_visited_uncached,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_cities_visited",
        user.cities_visited_uncached,
        expires_in: 1.day
      )

      # Preheat total_distance cache
      total_distance_meters = user.stats.sum(:distance)
      Rails.cache.write(
        "dawarich/user_#{user.id}_total_distance",
        Stat.convert_distance(total_distance_meters, user.safe_settings.distance_unit),
        expires_in: 1.day
      )

      # Preheat insights yearly digest cache
      Cache::PreheatInsightsDigests.new(user).call
    end
  end
end

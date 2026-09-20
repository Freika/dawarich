# frozen_string_literal: true

# Preheats the per-user caches read by the dashboard and Insights pages.
# Fanned out one-per-user by Cache::PreheatingJob so a single slow user
# cannot stall the whole nightly preheat.
class Cache::UserPreheatingJob < ApplicationJob
  queue_as :cache

  EXPIRES_IN = 1.day

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?

    write("dawarich/user_#{user.id}_years_tracked", user.years_tracked)
    write("dawarich/user_#{user.id}_points_geocoded_stats", StatsQuery.new(user).cached_points_geocoded_stats)
    write("dawarich/user_#{user.id}_countries_visited", user.countries_visited_uncached)
    write("dawarich/user_#{user.id}_cities_visited", user.cities_visited_uncached)
    write("dawarich/user_#{user.id}_total_distance", total_distance(user))

    Cache::PreheatInsightsDigests.new(user).call
  end

  private

  def write(key, value)
    Rails.cache.write(key, value, expires_in: EXPIRES_IN)
  end

  def total_distance(user)
    Stat.convert_distance(user.stats.sum(:distance), user.safe_settings.distance_unit)
  end
end

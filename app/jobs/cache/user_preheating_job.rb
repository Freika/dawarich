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

    write(Cache::UserKeys.years_tracked(user.id), user.years_tracked)
    write(Cache::UserKeys.points_geocoded_stats(user.id), StatsQuery.new(user).cached_points_geocoded_stats)
    write(Cache::UserKeys.countries_visited(user.id), user.countries_visited_uncached)
    write(Cache::UserKeys.cities_visited(user.id), user.cities_visited_uncached)

    Cache::PreheatInsightsDigests.new(user).call
  end

  private

  def write(key, value)
    Rails.cache.write(key, value, expires_in: EXPIRES_IN)
  end
end

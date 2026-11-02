# frozen_string_literal: true

class Cache::InvalidateUserCaches
  # Invalidates user-specific caches that depend on point data.
  # This should be called after:
  # - Reverse geocoding operations (updates country/city data)
  # - Stats calculations (updates geocoding stats)
  # - Bulk point imports/updates
  def initialize(user_id, year: nil)
    @user_id = user_id
    @year = year
  end

  def call
    invalidate_countries_visited
    invalidate_cities_visited
    invalidate_points_geocoded_stats
    invalidate_insights_digest
  end

  def invalidate_countries_visited
    Rails.cache.delete("dawarich/user_#{user_id}_countries_visited")
  end

  def invalidate_cities_visited
    Rails.cache.delete("dawarich/user_#{user_id}_cities_visited")
  end

  def invalidate_points_geocoded_stats
    Rails.cache.delete("dawarich/user_#{user_id}_points_geocoded_stats")
  end

  # Deletes the exact versioned keys instead of delete_matched, which scans the
  # whole Redis keyspace while holding a pooled connection. Entries under an
  # older updated_at are already unreachable and expire on their own.
  def invalidate_insights_digest
    digests = Users::Digest.yearly.where(user_id: user_id)
    digests = digests.where(year: year) if year
    keys = digests.map(&:insights_cache_key)
    Rails.cache.delete_multi(keys) if keys.any?
  end

  private

  attr_reader :user_id, :year
end

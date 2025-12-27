# frozen_string_literal: true

class Cache::InvalidateUserCaches
  # Invalidates user-specific caches that depend on point data.
  # This should be called after:
  # - Reverse geocoding operations (updates country/city data)
  # - Stats calculations (updates geocoding stats)
  # - Bulk point imports/updates
  def initialize(user_id)
    @user_id = user_id
  end

  def call
    invalidate_countries_visited
    invalidate_cities_visited
    invalidate_points_geocoded_stats
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

  private

  attr_reader :user_id
end

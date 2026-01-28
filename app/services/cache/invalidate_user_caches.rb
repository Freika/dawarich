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
    invalidate_total_distance
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

  def invalidate_total_distance
    Rails.cache.delete("dawarich/user_#{user_id}_total_distance")
  end

  def invalidate_insights_digest
    # Clear insights digest cache for specified year or all years
    # Note: delete_matched is supported by Redis cache store
    # The cache also auto-invalidates via timestamp-based keys when digests are updated
    return unless Rails.cache.respond_to?(:delete_matched)

    if year
      Rails.cache.delete_matched("insights/yearly_digest/#{user_id}/#{year}/*")
    else
      Rails.cache.delete_matched("insights/yearly_digest/#{user_id}/*")
    end
  end

  private

  attr_reader :user_id, :year
end

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
    cache.delete("dawarich/user_#{user_id}_countries_visited")
  end

  def invalidate_cities_visited
    cache.delete("dawarich/user_#{user_id}_cities_visited")
  end

  def invalidate_points_geocoded_stats
    cache.delete("dawarich/user_#{user_id}_points_geocoded_stats")
  end

  def invalidate_total_distance
    cache.delete("dawarich/user_#{user_id}_total_distance")
  end

  def invalidate_insights_digest
    # Clear insights digest cache for specified year or all years
    # Note: delete_matched is supported by Redis cache store
    # The cache also auto-invalidates via timestamp-based keys when digests are updated
    return unless cache.respond_to?(:delete_matched)

    if year
      cache.delete_matched("insights/yearly_digest/#{user_id}/#{year}/*")
    else
      cache.delete_matched("insights/yearly_digest/#{user_id}/*")
    end
  end

  private

  attr_reader :user_id, :year

  def cache
    @cache ||= begin
      store = Rails.cache
      if store.is_a?(ActiveSupport::Cache::RedisCacheStore)
        ActiveSupport::Cache::RedisCacheStore.new(
          **store.options,
          redis: store.redis,
          pool: false,
          error_handler: ->(exception:, **) { raise exception }
        )
      else
        store
      end
    end
  end
end

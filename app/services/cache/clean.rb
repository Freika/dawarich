# frozen_string_literal: true

class Cache::Clean
  class << self
    def call
      Rails.logger.info('Cleaning cache...')
      delete_control_flag
      delete_version_cache

      User.find_each do |user|
        delete_years_tracked_cache(user)
        delete_points_geocoded_stats_cache(user)
        delete_countries_cities_cache(user)
        delete_total_distance_cache(user)
      end

      Rails.logger.info('Cache cleaned')
    end

    private

    def delete_control_flag
      Rails.cache.delete('cache_jobs_scheduled')
    end

    def delete_version_cache
      Rails.cache.delete(CheckAppVersion::VERSION_CACHE_KEY)
    end

    def delete_years_tracked_cache(user)
      Rails.cache.delete("dawarich/user_#{user.id}_years_tracked")
    end

    def delete_points_geocoded_stats_cache(user)
      Rails.cache.delete("dawarich/user_#{user.id}_points_geocoded_stats")
    end

    def delete_countries_cities_cache(user)
      Rails.cache.delete("dawarich/user_#{user.id}_countries_visited")
      Rails.cache.delete("dawarich/user_#{user.id}_cities_visited")
    end

    def delete_total_distance_cache(user)
      Rails.cache.delete("dawarich/user_#{user.id}_total_distance")
    end
  end
end

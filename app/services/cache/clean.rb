# frozen_string_literal: true

class Cache::Clean
  class << self
    def call
      Rails.logger.info('Cleaning cache...')
      delete_control_flag
      delete_version_cache
      delete_years_tracked_cache
      delete_points_geocoded_stats_cache
      delete_countries_cities_cache
      delete_total_distance_cache
      Rails.logger.info('Cache cleaned')
    end

    private

    def delete_control_flag
      Rails.cache.delete('cache_jobs_scheduled')
    end

    def delete_version_cache
      Rails.cache.delete(CheckAppVersion::VERSION_CACHE_KEY)
    end

    def delete_years_tracked_cache
      User.find_each do |user|
        Rails.cache.delete("dawarich/user_#{user.id}_years_tracked")
      end
    end

    def delete_points_geocoded_stats_cache
      User.find_each do |user|
        Rails.cache.delete("dawarich/user_#{user.id}_points_geocoded_stats")
      end
    end

    def delete_countries_cities_cache
      User.find_each do |user|
        Rails.cache.delete("dawarich/user_#{user.id}_countries_visited")
        Rails.cache.delete("dawarich/user_#{user.id}_cities_visited")
      end
    end

    def delete_total_distance_cache
      User.find_each do |user|
        Rails.cache.delete("dawarich/user_#{user.id}_total_distance")
      end
    end
  end
end

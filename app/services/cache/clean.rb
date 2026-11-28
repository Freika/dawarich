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
        Cache::InvalidateUserCaches.new(user.id).invalidate_insights_digest
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
      Rails.cache.delete(Cache::UserKeys.years_tracked(user.id))
    end

    def delete_points_geocoded_stats_cache(user)
      Rails.cache.delete(Cache::UserKeys.points_geocoded_stats(user.id))
    end

    def delete_countries_cities_cache(user)
      Rails.cache.delete(Cache::UserKeys.countries_visited(user.id))
      Rails.cache.delete(Cache::UserKeys.cities_visited(user.id))
    end
  end
end

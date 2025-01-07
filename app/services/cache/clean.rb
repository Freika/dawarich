# frozen_string_literal: true

class Cache::Clean
  class << self
    def call
      Rails.logger.info('Cleaning cache...')
      delete_control_flag
      delete_version_cache
      delete_years_tracked_cache
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
  end
end

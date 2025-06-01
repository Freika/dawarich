# frozen_string_literal: true

Rails.application.config.after_initialize do
  # Only run in server mode and ensure one-time execution with atomic write
  if defined?(Rails::Server) && Rails.cache.write('cache_jobs_scheduled', true, unless_exist: true)
    # Clear the cache
    Cache::CleaningJob.perform_later

    # Preheat the cache
    Cache::PreheatingJob.perform_later
  end
end

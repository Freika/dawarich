# frozen_string_literal: true

# Load the Rails application.
require_relative 'application'

# Initialize the Rails application.
Rails.application.initialize!

# Use an atomic operation to ensure one-time execution
if defined?(Rails::Server) && Rails.cache.write('cache_jobs_scheduled', true, unless_exist: true)
  # Clear the cache
  Cache::CleaningJob.perform_later

  # Preheat the cache
  Cache::PreheatingJob.perform_later
end

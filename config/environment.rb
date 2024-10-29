# frozen_string_literal: true

# Load the Rails application.
require_relative 'application'

# Initialize the Rails application.
Rails.application.initialize!

# Clear the cache of the application version

Rails.cache.delete(CheckAppVersion::VERSION_CACHE_KEY)

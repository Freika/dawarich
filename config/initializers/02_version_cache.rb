# frozen_string_literal: true

# Defer cache operations until after initialization to avoid SolidCache loading issues
Rails.application.config.after_initialize do
  # Skip cache clearing when running the Rails console
  unless defined?(Rails::Console) || File.basename($PROGRAM_NAME) == 'rails' && ARGV.include?('console')
    Rails.cache.delete('dawarich/app-version-check') if Rails.cache.respond_to?(:delete)
  end
end

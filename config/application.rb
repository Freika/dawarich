# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dawarich
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = ENV.fetch('TIME_ZONE', 'Europe/Berlin')
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
    config.generators do |g|
      g.test_framework :rspec, fixture: false
      g.view_specs false
      g.routing_specs false
      g.helper_specs false
    end

    config.active_job.queue_adapter = :sidekiq

    config.action_mailer.preview_paths << Rails.root.join('spec/mailers/previews').to_s

    def self.env_or_dev_default(var, dev_default)
      return ENV[var] if ENV[var]
      return dev_default if !Rails.env.production? || ENV['SECRET_KEY_BASE_DUMMY']

      raise "#{var} required in production"
    end

    config.active_record.encryption.primary_key =
      env_or_dev_default('OTP_ENCRYPTION_PRIMARY_KEY',       'dawarich-dev-primary-key-not-for-production')
    config.active_record.encryption.deterministic_key =
      env_or_dev_default('OTP_ENCRYPTION_DETERMINISTIC_KEY', 'dawarich-dev-deterministic-not-for-prod')
    config.active_record.encryption.key_derivation_salt =
      env_or_dev_default('OTP_ENCRYPTION_KEY_DERIVATION_SALT', 'dawarich-dev-salt-not-for-production')
  end
end

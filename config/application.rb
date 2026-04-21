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

    # Default host and protocol for URL helpers in mailer views. Individual
    # environments (e.g. test) override this via `config.action_mailer.default_url_options`.
    # Missing APP_HOST raises in production so mail is never sent with a broken host.
    config.action_mailer.default_url_options = {
      host: ENV['APP_HOST'] ||
            (Rails.env.production? ? raise('APP_HOST required in production') : 'localhost:3000'),
      protocol: Rails.env.production? ? 'https' : 'http'
    }

    # Active Record Encryption is required by devise-two-factor for the `encrypts :otp_secret`
    # declaration on the User model. These keys must always be set for the model to load.
    #
    # 2FA is only user-facing when all three env vars are explicitly set (checked via
    # DawarichSettings.two_factor_available?). Without them, the 2FA settings page is hidden
    # and the OTP login challenge is skipped — but the model still needs encryption keys to boot.
    #
    # Set here (not in an initializer) so they are applied during Rails bootstrap before any
    # gem initializer (e.g., Flipper) forces ActiveRecord to boot eagerly. Otherwise the
    # on_load hook that copies these to ActiveRecord::Encryption.config fires with empty
    # values and `encrypts :otp_secret` fails at save time.
    config.active_record.encryption.primary_key =
      ENV['OTP_ENCRYPTION_PRIMARY_KEY'] || (if Rails.env.production?
                                              raise('OTP_ENCRYPTION_PRIMARY_KEY required in production')
                                            end

                                            'dawarich-dev-primary-key-not-for-production'
                                           )
    config.active_record.encryption.deterministic_key =
      ENV['OTP_ENCRYPTION_DETERMINISTIC_KEY'] || (if Rails.env.production?
                                                    raise('OTP_ENCRYPTION_DETERMINISTIC_KEY required in production')
                                                  end

                                                  'dawarich-dev-deterministic-not-for-prod'
                                                 )
    config.active_record.encryption.key_derivation_salt =
      ENV['OTP_ENCRYPTION_KEY_DERIVATION_SALT'] || (if Rails.env.production?
                                                      raise('OTP_ENCRYPTION_KEY_DERIVATION_SALT required in production')
                                                    end

                                                    'dawarich-dev-salt-not-for-production'
                                                   )
  end
end

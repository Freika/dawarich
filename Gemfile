# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read('.ruby-version').strip

gem 'activerecord-postgis-adapter', '11.1.1'
# https://meta.discourse.org/t/cant-rebuild-due-to-aws-sdk-gem-bump-and-new-aws-data-integrity-protections/354217/40
gem 'addressable', '>= 2.9.0'
gem 'apple_id', '~> 1.2'
gem 'aws-sdk-core', '~> 3.254', require: false
gem 'aws-sdk-kms', '~> 1.130', require: false
gem 'aws-sdk-s3', '~> 1.228', require: false
gem 'bcrypt', '>= 3.1.22'
gem 'bootsnap', require: false
gem 'chartkick'
gem 'connection_pool', '< 4' # Pin to 2.x - version 3.0+ has breaking API changes with Rails RedisCacheStore
gem 'data_migrate'
gem 'devise', '>= 5.0.4'
gem 'devise-two-factor'
gem 'faraday', '>= 2.14.2'
gem 'fit4ruby', '~> 3.13'
gem 'flipper', '~> 1.4'
gem 'flipper-active_record', '~> 1.4'
gem 'flipper-ui', '~> 1.4'
gem 'foreman'
gem 'geocoder', github: 'Freika/geocoder', branch: 'master'
gem 'google-id-token', '~> 1.4'
gem 'gpx'
gem 'groupdate'
gem 'h3', '~> 3.7'
gem 'httparty', '>= 0.24.0'
gem 'importmap-rails'
gem 'json', '>= 2.19.2'
gem 'jwt', '~> 2.10.3'
gem 'kaminari'
gem 'lograge'
gem 'net-imap', '>= 0.5.14'
gem 'oj'
gem 'omniauth-github', '~> 2.0.0'
gem 'omniauth-google-oauth2'
gem 'omniauth_openid_connect'
gem 'omniauth-rails_csrf_protection'
gem 'parallel'
gem 'pg'
gem 'posthog-rails'
gem 'posthog-ruby'
gem 'puma'
gem 'pundit', '>= 2.5.1'
gem 'rack-attack'
gem 'rack-cors'
gem 'rack-session', '>= 2.1.2'
gem 'rails', '~> 8.1.3'
gem 'rails_icons'
gem 'redis'
gem 'resolv-replace', '~> 0.2.0'
gem 'rexml'
gem 'rgeo'
gem 'rgeo-activerecord', '~> 8.1.0'
gem 'rgeo-geojson'
gem 'rqrcode', '~> 3.2'
gem 'rswag-api'
gem 'rswag-ui'
gem 'rubyzip', '~> 3.4'
gem 'sentry-rails', '>= 5.27.0'
gem 'sentry-ruby'
gem 'sidekiq', '8.1.6' # Pin to 8.0.x - sidekiq 8.1+ requires connection_pool 3.0+ breaking Rails
gem 'sidekiq-cron', '>= 2.4.0'
gem 'sidekiq-limit_fetch'
gem 'sprockets-rails'
gem 'stackprof'
gem 'stimulus-rails'
gem 'tailwindcss-rails', '= 3.3.2'
gem 'turbo-rails', '>= 2.0.17'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'webrick' # Required by Yabeda::Prometheus::Exporter.start_metrics_server! on Ruby 3.0+
gem 'with_advisory_lock'
gem 'yabeda-activerecord'
gem 'yabeda-prometheus'
gem 'yabeda-puma-plugin'
gem 'yabeda-rails'
gem 'yabeda-sidekiq'
gem 'zlib', '>= 3.2.3'

group :development, :test, :staging do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'ffaker'
  gem 'pry-byebug'
  gem 'pry-rails'
  gem 'rspec-rails', '>= 8.0.1'
  gem 'rswag-specs'
end

group :test do
  gem 'capybara'
  gem 'fakeredis'
  gem 'selenium-webdriver'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'super_diff'
  gem 'webmock'
end

group :development do
  gem 'database_consistency', '>= 2.0.5', require: false
  gem 'rubocop-rails', '>= 2.33.4', require: false
end

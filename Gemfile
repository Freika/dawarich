# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read('.ruby-version').strip

gem 'activerecord-postgis-adapter', '11.0'
# https://meta.discourse.org/t/cant-rebuild-due-to-aws-sdk-gem-bump-and-new-aws-data-integrity-protections/354217/40
gem 'aws-sdk-core', '~> 3.215.1', require: false
gem 'aws-sdk-kms', '~> 1.96.0', require: false
gem 'aws-sdk-s3', '~> 1.177.0', require: false
gem 'bootsnap', require: false
gem 'chartkick'
gem 'connection_pool', '< 3' # Pin to 2.x - version 3.0+ has breaking API changes with Rails RedisCacheStore
gem 'data_migrate'
gem 'devise'
gem 'foreman'
gem 'geocoder', github: 'Freika/geocoder', branch: 'master'
gem 'gpx'
gem 'groupdate'
gem 'h3', '~> 3.7'
gem 'httparty'
gem 'importmap-rails'
gem 'jwt', '~> 2.8'
gem 'kaminari'
gem 'lograge'
gem 'oj'
gem 'omniauth-github', '~> 2.0.0'
gem 'omniauth-google-oauth2'
gem 'omniauth_openid_connect'
gem 'omniauth-rails_csrf_protection'
gem 'parallel'
gem 'pg'
gem 'prometheus_exporter'
gem 'puma'
gem 'pundit', '>= 2.5.1'
gem 'rails', '~> 8.0'
gem 'rails_icons'
gem 'rails_pulse'
gem 'redis'
gem 'resolv-replace', '~> 0.2.0'
gem 'rexml'
gem 'rgeo'
gem 'rgeo-activerecord', '~> 8.0.0'
gem 'rgeo-geojson'
gem 'rqrcode', '~> 3.0'
gem 'rswag-api'
gem 'rswag-ui'
gem 'rubyzip', '~> 3.2'
gem 'sentry-rails', '>= 5.27.0'
gem 'sentry-ruby'
gem 'sidekiq', '8.0.10' # Pin to 8.0.x - sidekiq 8.1+ requires connection_pool 3.0+ breaking Rails
gem 'sidekiq-cron', '>= 2.3.1'
gem 'sidekiq-limit_fetch'
gem 'sprockets-rails'
gem 'stackprof'
gem 'stimulus-rails'
gem 'tailwindcss-rails', '= 3.3.2'
gem 'turbo-rails', '>= 2.0.17'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'with_advisory_lock'

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

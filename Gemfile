# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read('.ruby-version').strip

# https://meta.discourse.org/t/cant-rebuild-due-to-aws-sdk-gem-bump-and-new-aws-data-integrity-protections/354217/40
gem 'aws-sdk-s3', '~> 1.177.0', require: false
gem 'aws-sdk-core', '~> 3.215.1', require: false
gem 'aws-sdk-kms', '~> 1.96.0', require: false
gem 'bootsnap', require: false
gem 'chartkick'
gem 'data_migrate'
gem 'devise'
gem 'geocoder', github: 'Freika/geocoder', branch: 'master'
gem 'gpx'
gem 'groupdate'
gem 'httparty'
gem 'importmap-rails'
gem 'kaminari'
gem 'lograge'
gem 'oj'
gem 'pg'
gem 'prometheus_exporter'
gem 'activerecord-postgis-adapter'
gem 'puma'
gem 'pundit'
gem 'rails', '~> 8.0'
gem 'redis'
gem 'rexml'
gem 'rgeo'
gem 'rgeo-activerecord'
gem 'rgeo-geojson'
gem 'rswag-api'
gem 'rswag-ui'
gem 'sentry-ruby'
gem 'sentry-rails'
gem 'stackprof'
gem 'sidekiq'
gem 'sidekiq-cron'
gem 'sidekiq-limit_fetch'
gem 'sprockets-rails'
gem 'stimulus-rails'
gem 'strong_migrations'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'jwt'

group :development, :test do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'ffaker'
  gem 'pry-byebug'
  gem 'pry-rails'
  gem 'rspec-rails'
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
  gem 'database_consistency', require: false
  gem 'foreman'
  gem 'rubocop-rails', require: false
end

# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read('.ruby-version').strip

gem 'bootsnap', require: false
gem 'chartkick'
gem 'data_migrate'
gem 'devise'
gem 'geocoder', git: 'https://github.com/alexreisner/geocoder.git', ref: '04ee293'
gem 'gpx'
gem 'groupdate'
gem 'httparty'
gem 'importmap-rails'
gem 'kaminari'
gem 'lograge'
gem 'oj'
gem 'pg'
gem 'prometheus_exporter'
gem 'puma'
gem 'pundit'
gem 'rails'
gem 'rswag-api'
gem 'rswag-ui'
gem 'shrine', '~> 3.6'
gem 'sidekiq'
gem 'sidekiq-cron'
gem 'sprockets-rails'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

group :development, :test do
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
  gem 'fakeredis'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'super_diff'
  gem 'webmock'
end

group :development do
  gem 'foreman'
  gem 'rubocop-rails', require: false
end

# Use Redis for Action Cable
gem 'redis'

# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.3'
gem 'bootsnap', require: false
gem 'devise'
gem 'pg'
gem 'puma'
gem 'pundit'
gem 'rails'
gem 'sprockets-rails'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem "importmap-rails"
gem "chartkick"
gem 'geocoder'
gem 'sidekiq'


group :development, :test do
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'factory_bot_rails'
  gem 'ffaker'
  gem 'rspec-rails'
  gem 'dotenv-rails'
  gem 'pry-byebug'
  gem 'pry-rails'
end

group :test do
  gem 'shoulda-matchers'
  gem 'simplecov'
end

group :development do
  gem 'foreman'
  gem 'rubocop-rails', require: false
end

# Use Redis for Action Cable
gem "redis"

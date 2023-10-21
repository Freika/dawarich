# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.2'
gem 'bootsnap', require: false
gem 'devise', '4.9.2'
gem 'pg', '~> 1.1'
gem 'puma', '~> 6.4'
gem 'pundit', '~> 2.2'
gem 'rails', '7.1.1'
gem 'sprockets-rails'
gem 'strong_migrations'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem "importmap-rails", "~> 1.2"

group :development, :test do
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'factory_bot_rails'
  gem 'ffaker', '2.20.0'
  gem 'rspec-rails', '~> 5.1.0'
end

group :test do
  gem 'shoulda-matchers', '~> 5.1'
  gem 'simplecov', '~> 0.21'
end

group :development do
  gem 'foreman'
  gem 'rubocop-rails', require: false
end

# Use Redis for Action Cable
gem "redis", "~> 4.0"

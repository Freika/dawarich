# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.1.0'
gem 'bootsnap', require: false
gem 'devise', '4.8.1'
gem 'pg', '~> 1.1'
gem 'puma', '~> 5.0'
gem 'rails', '7.0.4'
gem 'sprockets-rails'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

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

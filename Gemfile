source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.1.0'
gem 'rails', '~> 7.0.2', '>= 7.0.2.3'
gem 'pg', '~> 1.1'
gem 'puma', '~> 5.0'
gem 'tzinfo-data', platforms: %i[ mingw mswin x64_mingw jruby ]
gem 'bootsnap', require: false
gem 'sprockets-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'devise', '4.8.1'

group :development, :test do
  gem 'debug', platforms: %i[ mri mingw x64_mingw ]
  gem 'rspec-rails', '~> 5.0.0'
  gem 'factory_bot_rails'
  gem 'ffaker', '2.20.0'
end

group :test do
  gem 'simplecov', '~> 0.21'
  gem 'shoulda-matchers', '~> 5.1'
end

group :development do
  gem 'foreman'
end

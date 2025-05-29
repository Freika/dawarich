# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'rswag/specs'
require 'sidekiq/testing'
require 'super_diff/rspec-rails'

require 'rake'

Rails.application.load_tasks
# Add additional requires below this line. Rails is not loaded until this point!

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system

  config.rswag_dry_run = false

  config.before do
    ActiveJob::Base.queue_adapter = :test
    allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
  end

  config.before(:each, type: :system) do
    # Configure Capybara for CI environments
    if ENV['CI']
      # Setup for CircleCI
      driven_by :selenium, using: :headless_chrome, options: {
        browser: :remote,
        url: "http://chrome:4444/wd/hub",
        options: {
          args: %w[headless disable-gpu no-sandbox disable-dev-shm-usage]
        }
      }
    else
      # Local environment configuration
      driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
    end

    # Disable transactional fixtures for system tests
    self.use_transactional_tests = false
    # Completely disable WebMock for system tests to allow Selenium WebDriver connections
    WebMock.disable!
  end

  config.after(:each, type: :system) do
    # Clean up database after system tests
    ActiveRecord::Base.connection.truncate_tables(*ActiveRecord::Base.connection.tables)
    # Re-enable WebMock after system tests
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  config.after(:suite) do
    Rake::Task['rswag:generate'].invoke
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

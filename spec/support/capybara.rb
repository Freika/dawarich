# frozen_string_literal: true

require 'capybara/rails'
require 'capybara/rspec'
require 'selenium-webdriver'

# Configure Capybara timeouts to be more lenient in CI environments
Capybara.default_max_wait_time = ENV['CI'] ? 15 : 5
Capybara.server = :puma, { Silent: true }

# For debugging in CI
if ENV['CI']
  Capybara.register_driver :selenium_chrome_headless do |app|
    browser_options = ::Selenium::WebDriver::Chrome::Options.new
    browser_options.add_argument('--headless')
    browser_options.add_argument('--no-sandbox')
    browser_options.add_argument('--disable-dev-shm-usage')
    browser_options.add_argument('--disable-gpu')
    browser_options.add_argument('--window-size=1400,1400')

    Capybara::Selenium::Driver.new(
      app,
      browser: :chrome,
      options: browser_options
    )
  end
end

# Allow for selenium remote driver based on environment variables
Capybara.register_driver :selenium_remote_chrome do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    'goog:chromeOptions' => {
      'args' => %w[headless no-sandbox disable-dev-shm-usage disable-gpu window-size=1400,1400]
    }
  )

  Capybara::Selenium::Driver.new(
    app,
    browser: :remote,
    url: 'http://chrome:4444/wd/hub',
    capabilities: capabilities
  )
end

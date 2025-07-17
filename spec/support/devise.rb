# frozen_string_literal: true

# Standard Devise test helpers configuration for request specs

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system

  # Ensure Devise routes are loaded before request specs
  config.before(:each, type: :request) do
    # Reload routes to ensure Devise mappings are available
    Rails.application.reload_routes! unless @routes_reloaded
    @routes_reloaded = true
  end
end

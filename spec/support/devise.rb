# frozen_string_literal: true

# Standard Devise test helpers configuration for request specs

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::ControllerHelpers, type: :controller

  # Ensure anonymous controllers in controller specs have Warden available
  config.before(:each, type: :controller) do
    @request.env['devise.mapping'] = Devise.mappings[:user] if @request
  end

end

# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    # Clear the cache before each test
    Rails.cache.clear
  end
end

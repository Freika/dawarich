# frozen_string_literal: true

# Stub GitHub API requests in tests
RSpec.configure do |config|
  config.before(:each) do
    # Stub GitHub API version checking
    stub_request(:get, "https://api.github.com/repos/Freika/dawarich/tags")
      .to_return(
        status: 200,
        body: [{ name: "v0.1.0" }].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end

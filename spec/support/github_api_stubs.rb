# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:get, "https://api.github.com/repos/Freika/dawarich/tags")
      .to_return(
        status: 200,
        body: '[{"name": "1.0.0"}]',
        headers: {}
      )
  end
end

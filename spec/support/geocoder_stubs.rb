# frozen_string_literal: true

# Stub all Geocoder requests in tests
RSpec.configure do |config|
  config.before(:each) do
    # Create a generic stub for all Geocoder requests
    allow(Geocoder).to receive(:search).and_return(
      [
        double(
          data: {
            'properties' => {
              'countrycode' => 'US',
              'country' => 'United States',
              'state' => 'New York',
              'name' => 'Test Location'
            }
          }
        )
      ]
    )
  end
end

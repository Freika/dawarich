# frozen_string_literal: true

# Stub all Geocoder requests in tests
RSpec.configure do |config|
  config.before(:each) do
    # Create a generic stub for all Geocoder requests
    stub_request(:any, %r{photon\.dawarich\.app/reverse}).to_return(
      status: 200,
      body: {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            properties: {
              name: 'Test Location',
              countrycode: 'US',
              country: 'United States',
              state: 'New York'
            },
            geometry: {
              coordinates: [-73.9, 40.7],
              type: 'Point'
            }
          }
        ]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end
end

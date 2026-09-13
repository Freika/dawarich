# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bounded place search with normalized provider results' do
  let(:user) { create(:user) }
  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
    allow(Geocoder).to receive(:search).and_call_original
    allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
  end

  def flat_result(name:, latitude:)
    {
      'lat' => latitude.to_s, 'lon' => lon.to_s, 'name' => name,
      'type' => 'cafe', 'class' => 'amenity', 'osm_id' => 123, 'osm_type' => 'node',
      'address' => { 'road' => 'Example Road', 'house_number' => '7', 'city' => 'Berlin', 'country' => 'Germany' }
    }
  end

  def geojson_result(name:, latitude:)
    {
      'type' => 'Feature',
      'geometry' => { 'type' => 'Point', 'coordinates' => [lon, latitude] },
      'properties' => { 'name' => name, 'street' => 'Example Road', 'housenumber' => '7',
                        'city' => 'Berlin', 'country' => 'Germany', 'osm_id' => 123, 'osm_type' => 'N' }
    }
  end

  {
    photon: ['https://photon.example.com/api', { 'bbox' => /\A[-\d.,]+\z/ }],
    nominatim: ['https://nominatim.example.com/search', { 'viewbox' => /\A[-\d.,]+\z/, 'bounded' => '1' }],
    locationiq: ['https://us1.locationiq.com/v1/search.php', { 'viewbox' => /\A[-\d.,]+\z/, 'bounded' => '1' }],
    geoapify: ['https://api.geoapify.com/v1/geocode/search', { 'filter' => /\Arect:/ }]
  }.each do |provider, (endpoint, spatial_query)|
    context "with #{provider}" do
      before do
        traits = provider == :photon ? [:active] : [:active, provider]
        create(:service_setting, *traits, user: user)
      end

      it 'sends spatial constraints and returns normalized nearby addresses in distance order' do
        flat = %i[nominatim locationiq].include?(provider)
        builder = flat ? :flat_result : :geojson_result
        features = [
          send(builder, name: 'Distant Place', latitude: 53.5),
          send(builder, name: 'Coffee Shop', latitude: lat + 0.004),
          send(builder, name: nil, latitude: lat)
        ]
        body = flat ? features : { type: 'FeatureCollection', features: features }
        request = stub_request(:get, endpoint)
                  .with(query: hash_including(spatial_query))
                  .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })

        results = Places::Search.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call

        expect(request).to have_been_requested.once
        expect(results.map { |place| place[:name] }).to eq(['Example Road 7', 'Coffee Shop'])
        expect(results.first).to include(latitude: lat, longitude: lon, street: 'Example Road',
                                         housenumber: '7', city: 'Berlin', country: 'Germany')
      end
    end
  end
end

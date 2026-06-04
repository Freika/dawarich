# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe Places::PhotonResultFormatter do
  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  let(:photon_result) do
    instance_double(
      Geocoder::Result::Photon,
      data: {
        'properties' => {
          'osm_id' => 1_234_567, 'osm_type' => 'N', 'osm_key' => 'amenity',
          'osm_value' => 'cafe', 'name' => 'Café Bravo', 'city' => 'Berlin',
          'country' => 'Germany', 'street' => 'Bergmannstraße', 'housenumber' => '1',
          'postcode' => '10961'
        },
        'geometry' => { 'coordinates' => [lon, lat], 'type' => 'Point' }
      }
    )
  end

  describe '.call' do
    it 'flattens a Photon result into the select_place-compatible shape' do
      result = described_class.call(photon_result, fallback_lat: 0.0, fallback_lon: 0.0)

      expect(result).to include(
        id: nil, name: 'Café Bravo', latitude: lat, longitude: lon,
        osm_id: 1_234_567, osm_type: 'N', osm_key: 'amenity', osm_value: 'cafe',
        city: 'Berlin', country: 'Germany', street: 'Bergmannstraße',
        housenumber: '1', postcode: '10961', source: 'photon'
      )
      expect(result[:geodata]).to eq(photon_result.data)
    end

    it 'falls back to the supplied coordinates when geometry is missing' do
      bare = instance_double(Geocoder::Result::Photon, data: { 'properties' => { 'name' => 'X' } })

      result = described_class.call(bare, fallback_lat: lat, fallback_lon: lon)

      expect(result[:latitude]).to eq(lat)
      expect(result[:longitude]).to eq(lon)
    end

    it 'derives a name from street/housenumber, then city, then a default' do
      no_name = instance_double(
        Geocoder::Result::Photon,
        data: { 'properties' => { 'street' => 'Sterndamm', 'housenumber' => '7' } }
      )
      city_only = instance_double(Geocoder::Result::Photon, data: { 'properties' => { 'city' => 'Berlin' } })
      empty = instance_double(Geocoder::Result::Photon, data: { 'properties' => {} })

      expect(described_class.call(no_name, fallback_lat: lat, fallback_lon: lon)[:name]).to eq('Sterndamm 7')
      expect(described_class.call(city_only, fallback_lat: lat, fallback_lon: lon)[:name]).to eq('Berlin')
      expect(described_class.call(empty, fallback_lat: lat, fallback_lon: lon)[:name]).to eq('Unknown Place')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::ResultNormalizer do
  describe '.call' do
    it 'normalizes a Photon (GeoJSON) result' do
      result = double(data: {
                        'type' => 'Feature',
                        'geometry' => { 'type' => 'Point', 'coordinates' => [9.5, 47.1] },
                        'properties' => {
                          'osm_id' => 123, 'osm_type' => 'N', 'osm_key' => 'amenity',
                          'osm_value' => 'cafe', 'name' => 'Café', 'city' => 'Vaduz',
                          'country' => 'Liechtenstein', 'street' => 'Städtle', 'housenumber' => '1',
                          'postcode' => '9490'
                        }
                      })

      expect(described_class.call(result)).to eq(
        properties: {
          'name' => 'Café', 'street' => 'Städtle', 'housenumber' => '1', 'city' => 'Vaduz',
          'country' => 'Liechtenstein', 'postcode' => '9490', 'osm_id' => 123, 'osm_type' => 'N',
          'osm_key' => 'amenity', 'osm_value' => 'cafe'
        },
        coords: [9.5, 47.1]
      )
    end

    it 'normalizes a Nominatim (flat) result' do
      result = double(data: {
                        'place_id' => 42, 'lat' => '47.1', 'lon' => '9.5', 'name' => 'Café',
                        'category' => 'amenity', 'type' => 'cafe', 'osm_id' => 123, 'osm_type' => 'way',
                        'display_name' => 'Café, Städtle 1, Vaduz, Liechtenstein',
                        'address' => {
                          'road' => 'Städtle', 'house_number' => '1', 'city' => 'Vaduz',
                          'country' => 'Liechtenstein', 'postcode' => '9490'
                        }
                      })

      expect(described_class.call(result)).to eq(
        properties: {
          'name' => 'Café', 'street' => 'Städtle', 'housenumber' => '1', 'city' => 'Vaduz',
          'country' => 'Liechtenstein', 'postcode' => '9490', 'osm_id' => 123, 'osm_type' => 'way',
          'osm_key' => 'amenity', 'osm_value' => 'cafe'
        },
        coords: [9.5, 47.1]
      )
    end

    it 'falls back to the properties lat/lon when the GeoJSON geometry is absent' do
      result = double(data: {
                        'type' => 'Feature',
                        'properties' => { 'name' => 'Café', 'lat' => 47.1, 'lon' => 9.5 }
                      })

      expect(described_class.call(result)[:coords]).to eq([9.5, 47.1])
    end

    it 'returns empty fields for blank data' do
      expect(described_class.call(double(data: nil))).to eq(properties: {}, coords: nil)
    end

    it 'normalizes raw geodata hashes via .from_data' do
      raw = {
        'place_id' => 42, 'lat' => '47.1', 'lon' => '9.5', 'name' => 'Café',
        'category' => 'amenity', 'type' => 'cafe',
        'address' => { 'road' => 'Städtle', 'house_number' => '1', 'city' => 'Vaduz',
                       'country' => 'Liechtenstein', 'postcode' => '9490' }
      }

      expect(described_class.from_data(raw)).to eq(
        properties: {
          'name' => 'Café', 'street' => 'Städtle', 'housenumber' => '1', 'city' => 'Vaduz',
          'country' => 'Liechtenstein', 'postcode' => '9490', 'osm_id' => nil, 'osm_type' => nil,
          'osm_key' => 'amenity', 'osm_value' => 'cafe'
        },
        coords: [9.5, 47.1]
      )
      expect(described_class.from_data(nil)).to eq(properties: {}, coords: nil)
    end

    it 'unwraps a FeatureCollection to its first feature' do
      raw = {
        'type' => 'FeatureCollection',
        'features' => [{
          'type' => 'Feature',
          'geometry' => { 'type' => 'Point', 'coordinates' => [9.5, 47.1] },
          'properties' => { 'name' => 'Café', 'city' => 'Vaduz' }
        }]
      }

      fields = described_class.from_data(raw)
      expect(fields[:properties]['name']).to eq('Café')
      expect(fields[:coords]).to eq([9.5, 47.1])
    end
  end
end

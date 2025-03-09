# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PlaceSerializer do
  describe '#call' do
    let(:place) do
      instance_double(
        Place,
        id: 123,
        name: 'Central Park',
        lon: -73.9665,
        lat: 40.7812,
        city: 'New York',
        country: 'United States',
        source: 'osm',
        geodata: { 'amenity' => 'park', 'leisure' => 'park' },
        reverse_geocoded_at: Time.zone.parse('2023-01-15T12:00:00Z')
      )
    end

    subject(:serializer) { described_class.new(place) }

    it 'initializes with a place object' do
      expect(serializer.instance_variable_get(:@place)).to eq(place)
    end

    it 'serializes a place into a hash with all attributes' do
      result = serializer.call

      expect(result).to be_a(Hash)
      expect(result[:id]).to eq(123)
      expect(result[:name]).to eq('Central Park')
      expect(result[:longitude]).to eq(-73.9665)
      expect(result[:latitude]).to eq(40.7812)
      expect(result[:city]).to eq('New York')
      expect(result[:country]).to eq('United States')
      expect(result[:source]).to eq('osm')
      expect(result[:geodata]).to eq({ 'amenity' => 'park', 'leisure' => 'park' })
      expect(result[:reverse_geocoded_at]).to eq(Time.zone.parse('2023-01-15T12:00:00Z'))
    end

    context 'with nil values' do
      let(:place_with_nils) do
        instance_double(
          Place,
          id: 456,
          name: 'Unknown Place',
          lon: nil,
          lat: nil,
          city: nil,
          country: nil,
          source: nil,
          geodata: nil,
          reverse_geocoded_at: nil
        )
      end

      subject(:serializer_with_nils) { described_class.new(place_with_nils) }

      it 'handles nil values correctly' do
        result = serializer_with_nils.call

        expect(result[:id]).to eq(456)
        expect(result[:name]).to eq('Unknown Place')
        expect(result[:longitude]).to be_nil
        expect(result[:latitude]).to be_nil
        expect(result[:city]).to be_nil
        expect(result[:country]).to be_nil
        expect(result[:source]).to be_nil
        expect(result[:geodata]).to be_nil
        expect(result[:reverse_geocoded_at]).to be_nil
      end
    end

    context 'with actual Place model', type: :model do
      let(:real_place) { create(:place) }
      subject(:real_serializer) { described_class.new(real_place) }

      it 'serializes a real place model correctly' do
        result = real_serializer.call

        expect(result[:id]).to eq(real_place.id)
        expect(result[:name]).to eq(real_place.name)
        expect(result[:longitude]).to eq(real_place.lon)
        expect(result[:latitude]).to eq(real_place.lat)
        expect(result[:city]).to eq(real_place.city)
        expect(result[:country]).to eq(real_place.country)
        expect(result[:source]).to eq(real_place.source)
        expect(result[:geodata]).to eq(real_place.geodata)
        expect(result[:reverse_geocoded_at]).to eq(real_place.reverse_geocoded_at)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PlaceSerializer do
  describe '#call' do
    let(:place) do
      create(
        :place,
        :with_geodata,
        name: 'Central Park',
        longitude: -73.9665,
        latitude: 40.7812,
        lonlat: 'SRID=4326;POINT(-73.9665 40.7812)',
        city: 'New York',
        country: 'United States',
        source: 'photon',
        geodata: { 'amenity' => 'park', 'leisure' => 'park' },
        reverse_geocoded_at: Time.zone.parse('2023-01-15T12:00:00Z')
      )
    end

    subject(:serializer) { described_class.new(place) }

    it 'serializes a place into a hash with all attributes' do
      result = serializer.call

      expect(result).to be_a(Hash)
      expect(result[:id]).to eq(place.id)
      expect(result[:name]).to eq('Central Park')
      expect(result[:longitude]).to eq(-73.9665)
      expect(result[:latitude]).to eq(40.7812)
      expect(result[:city]).to eq('New York')
      expect(result[:country]).to eq('United States')
      expect(result[:source]).to eq('photon')
      expect(result[:geodata]).to eq({ 'amenity' => 'park', 'leisure' => 'park' })
      expect(result[:reverse_geocoded_at]).to eq(Time.zone.parse('2023-01-15T12:00:00Z'))
    end

    context 'with nil values' do
      let(:place_with_nils) do
        create(
          :place,
          name: 'Unknown Place',
          city: nil,
          country: nil,
          source: nil,
          geodata: {},
          reverse_geocoded_at: nil
        )
      end

      subject(:serializer_with_nils) { described_class.new(place_with_nils) }

      it 'handles nil values correctly' do
        result = serializer_with_nils.call

        expect(result[:id]).to eq(place_with_nils.id)
        expect(result[:name]).to eq('Unknown Place')
        expect(result[:city]).to be_nil
        expect(result[:country]).to be_nil
        expect(result[:source]).to be_nil
        expect(result[:geodata]).to eq({})
        expect(result[:reverse_geocoded_at]).to be_nil
      end
    end
  end
end

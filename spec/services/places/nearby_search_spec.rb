# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe Places::NearbySearch do
  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

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

  describe '#call' do
    it 'returns hashes with id, source, geodata keys' do
      allow(Geocoder).to receive(:search).and_return([photon_result])

      result = described_class.new(latitude: lat, longitude: lon).call

      expect(result.first).to include(
        id: nil,
        name: 'Café Bravo',
        source: 'photon',
        osm_id: 1_234_567
      )
      expect(result.first[:geodata]).to eq(photon_result.data)
    end

    it 'returns [] when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
    end

    it 'returns [] when coordinates are zero (degenerate visit)' do
      expect(Geocoder).not_to receive(:search)

      expect(described_class.new(latitude: 0.0, longitude: 0.0).call).to eq([])
    end

    it 'handles invalid provider requests without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error/)
    end

    it 'reports unexpected errors and returns []' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).to have_received(:call)
    end

    context 'with cache: true' do
      before { Rails.cache.clear }

      it 'hits Geocoder only once for repeated calls within TTL' do
        allow(Geocoder).to receive(:search).and_return([photon_result])

        described_class.new(latitude: lat, longitude: lon, cache: true).call
        described_class.new(latitude: lat, longitude: lon, cache: true).call

        expect(Geocoder).to have_received(:search).once
      end
    end

    context 'with cache: false (default)' do
      it 'hits Geocoder on every call' do
        allow(Geocoder).to receive(:search).and_return([photon_result])

        described_class.new(latitude: lat, longitude: lon).call
        described_class.new(latitude: lat, longitude: lon).call

        expect(Geocoder).to have_received(:search).twice
      end
    end
  end
end

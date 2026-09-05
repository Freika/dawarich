# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::GeocodingService do
  let(:query) { 'Kaufland Berlin' }
  let(:user) { create(:user) }
  let(:service) { described_class.new(query, user: user) }

  describe '#search' do
    context 'with valid query' do
      let(:mock_geocoder_result) do
        double(
          'Geocoder::Result',
          latitude: 52.5200,
          longitude: 13.4050,
          address: 'Kaufland, Alexanderplatz 1, Berlin',
          data: {
            'type' => 'shop',
            'osm_id' => '12345',
            'place_rank' => 30,
            'importance' => 0.8
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoder_result])
        allow(Geocoder.config).to receive(:lookup).and_return(:photon)
      end

      it 'returns normalized geocoding results' do
        results = service.search

        expect(results).to be_an(Array)
        expect(results.first).to include(
          lat: 52.5200,
          lon: 13.4050,
          name: 'Kaufland',
          address: 'Kaufland, Alexanderplatz 1, Berlin',
          type: 'shop'
        )
      end

      it 'includes provider data' do
        results = service.search

        expect(results.first[:provider_data]).to include(
          osm_id: '12345',
          place_rank: 30,
          importance: 0.8
        )
      end

      it 'limits results to MAX_RESULTS' do
        expect(Geocoder).to receive(:search)
          .with(query, hash_including(limit: 10, timeout: FORWARD_GEOCODING_TIMEOUT))

        service.search
      end
    end

    context 'with blank query' do
      let(:service) { described_class.new('', user: user) }

      it 'returns empty array' do
        expect(service.search).to eq([])
      end
    end

    context 'when Geocoder returns no results' do
      before do
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'returns empty array' do
        expect(service.search).to eq([])
      end
    end

    context 'when Geocoder raises an error' do
      before do
        allow(Geocoder).to receive(:search).and_raise(StandardError.new('Geocoding error'))
      end

      it 'handles error gracefully and returns empty array' do
        expect(service.search).to eq([])
      end
    end

    context 'with invalid coordinates' do
      let(:invalid_result) do
        double(
          'Geocoder::Result',
          latitude: 91.0, # Invalid latitude
          longitude: 13.4050,
          address: 'Invalid location',
          data: {}
        )
      end

      let(:valid_result) do
        double(
          'Geocoder::Result',
          latitude: 52.5200,
          longitude: 13.4050,
          address: 'Valid location',
          data: {}
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([invalid_result, valid_result])
      end

      it 'filters out results with invalid coordinates' do
        results = service.search

        expect(results.length).to eq(1)
        expect(results.first[:lat]).to eq(52.5200)
      end
    end

    describe '#deduplicate_results' do
      let(:duplicate_results) do
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Location 1',
            address: 'Address 1',
            type: 'shop',
            provider_data: {}
          },
          {
            lat: 52.5201, # Within 100m of first location
            lon: 13.4051,
            name: 'Location 2',
            address: 'Address 2',
            type: 'shop',
            provider_data: {}
          }
        ]
      end

      let(:mock_results) do
        duplicate_results.map do |result|
          double(
            'Geocoder::Result',
            latitude: result[:lat],
            longitude: result[:lon],
            address: result[:address],
            data: { 'type' => result[:type] }
          )
        end
      end

      before do
        allow(Geocoder).to receive(:search).and_return(mock_results)
      end

      it 'removes locations within 100m of each other' do
        service = described_class.new('test', user: user)
        results = service.search

        expect(results.length).to eq(1)
        expect(results.first[:name]).to eq('Address 1')
      end
    end
  end

  describe '#provider_name' do
    before do
      allow(Geocoder.config).to receive(:lookup).and_return(:nominatim)
    end

    it 'returns the current geocoding provider name' do
      expect(service.provider_name).to eq('Nominatim')
    end
  end

  describe 'user mode (no ENV)' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      allow(Geocoder).to receive(:search).and_call_original
      allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
    end

    it 'uses the user provider for search and names it' do
      create(:service_setting, :geoapify, :active, user: user)
      stub_request(:get, %r{https://api\.geoapify\.com/v1/geocode/search})
        .to_return(status: 200, body: { type: 'FeatureCollection', features: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new('Leipzig', user: user).search

      expect(WebMock).to have_requested(:get, /api\.geoapify\.com/)
      expect(described_class.new('Leipzig', user: user).provider_name).to eq('Geoapify')
    end

    it 'falls back to the default public lookup for unconfigured users' do
      stub_request(:get, /nominatim\.openstreetmap\.org/)
        .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })

      described_class.new('Leipzig', user: user).search

      expect(WebMock).to have_requested(:get, /nominatim\.openstreetmap\.org/)
    end
  end
end

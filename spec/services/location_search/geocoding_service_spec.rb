# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::GeocodingService do
  let(:service) { described_class.new }

  describe '#search' do
    context 'with valid query' do
      let(:query) { 'Kaufland Berlin' }
      let(:mock_geocoder_result) do
        double(
          'Geocoder::Result',
          latitude: 52.5200,
          longitude: 13.4050,
          address: 'Kaufland, Alexanderplatz 1, Berlin',
          data: {
            'properties' => {
              'name' => 'Kaufland Mitte',
              'street' => 'Alexanderplatz',
              'housenumber' => '1',
              'city' => 'Berlin',
              'country' => 'Germany',
              'osm_key' => 'shop',
              'osm_id' => '12345'
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([mock_geocoder_result])
        allow(Geocoder.config).to receive(:lookup).and_return(:photon)
      end

      it 'returns normalized geocoding results' do
        results = service.search(query)

        expect(results).to be_an(Array)
        expect(results.first).to include(
          lat: 52.5200,
          lon: 13.4050,
          name: 'Kaufland Mitte',
          address: 'Alexanderplatz, 1, Berlin, Germany',
          type: 'shop'
        )
      end

      it 'includes provider data' do
        results = service.search(query)

        expect(results.first[:provider_data]).to include(
          osm_id: '12345',
          osm_type: nil
        )
      end

      it 'caches results' do
        expect(Rails.cache).to receive(:fetch).and_call_original

        service.search(query)
      end

      it 'limits results to MAX_RESULTS' do
        expect(Geocoder).to receive(:search).with(query, limit: 10)

        service.search(query)
      end

      context 'with cached results' do
        let(:cached_results) { [{ lat: 1.0, lon: 2.0, name: 'Cached' }] }

        before do
          allow(Rails.cache).to receive(:fetch).and_return(cached_results)
        end

        it 'returns cached results without calling Geocoder' do
          expect(Geocoder).not_to receive(:search)

          results = service.search(query)
          expect(results).to eq(cached_results)
        end
      end
    end

    context 'with blank query' do
      it 'returns empty array' do
        results = service.search('')
        expect(results).to eq([])
        
        results = service.search(nil)
        expect(results).to eq([])
      end
    end

    context 'when Geocoder returns no results' do
      before do
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'returns empty array' do
        results = service.search('nonexistent place')
        expect(results).to eq([])
      end
    end

    context 'when Geocoder raises an error' do
      before do
        allow(Geocoder).to receive(:search).and_raise(StandardError.new('API error'))
      end

      it 'handles error gracefully and returns empty array' do
        expect(Rails.logger).to receive(:error).with(/Geocoding search failed/)

        results = service.search('test query')
        expect(results).to eq([])
      end
    end

    context 'with invalid coordinates' do
      let(:invalid_result) do
        double(
          'Geocoder::Result',
          latitude: 91.0,  # Invalid latitude
          longitude: 181.0, # Invalid longitude
          address: 'Invalid Location',
          data: {}
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([invalid_result])
      end

      it 'filters out results with invalid coordinates' do
        results = service.search('test')
        expect(results).to be_empty
      end
    end

    describe '#deduplicate_results' do
      let(:duplicate_results) do
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Location A',
            address: 'Address A',
            type: 'shop'
          },
          {
            lat: 52.5201, # Very close to first location (~11 meters)
            lon: 13.4051,
            name: 'Location B',
            address: 'Address B',
            type: 'shop'
          },
          {
            lat: 52.5300, # Far from others
            lon: 13.4150,
            name: 'Location C',
            address: 'Address C',
            type: 'restaurant'
          }
        ]
      end

      before do
        allow(service).to receive(:perform_geocoding_search).and_return(duplicate_results)
      end

      it 'removes locations within 100m of each other' do
        results = service.search('test')

        expect(results.length).to eq(2)
        expect(results.map { |r| r[:name] }).to include('Location A', 'Location C')
      end
    end
  end

  describe '#provider_name' do
    it 'returns the current geocoding provider name' do
      allow(Geocoder.config).to receive(:lookup).and_return(:photon)

      expect(service.provider_name).to eq('Photon')
    end
  end

  describe 'provider-specific extraction' do
    context 'with Photon provider' do
      let(:photon_result) do
        double(
          'Geocoder::Result',
          latitude: 52.5200,
          longitude: 13.4050,
          data: {
            'properties' => {
              'name' => 'Kaufland',
              'street' => 'Alexanderplatz',
              'housenumber' => '1',
              'city' => 'Berlin',
              'state' => 'Berlin',
              'country' => 'Germany'
            }
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([photon_result])
        allow(Geocoder.config).to receive(:lookup).and_return(:photon)
      end

      it 'extracts Photon-specific data correctly' do
        results = service.search('test')

        expect(results.first[:name]).to eq('Kaufland')
        expect(results.first[:address]).to eq('Alexanderplatz, 1, Berlin, Berlin, Germany')
      end
    end

    context 'with Nominatim provider' do
      let(:nominatim_result) do
        double(
          'Geocoder::Result',
          latitude: 52.5200,
          longitude: 13.4050,
          data: {
            'display_name' => 'Kaufland, Alexanderplatz 1, Berlin, Germany',
            'type' => 'shop',
            'class' => 'amenity'
          }
        )
      end

      before do
        allow(Geocoder).to receive(:search).and_return([nominatim_result])
        allow(Geocoder.config).to receive(:lookup).and_return(:nominatim)
      end

      it 'extracts Nominatim-specific data correctly' do
        results = service.search('test')

        expect(results.first[:name]).to eq('Kaufland')
        expect(results.first[:address]).to eq('Kaufland, Alexanderplatz 1, Berlin, Germany')
        expect(results.first[:type]).to eq('shop')
      end
    end
  end
end
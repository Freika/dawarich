# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::PointFinder do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, search_params) }
  let(:search_params) { { query: 'Kaufland' } }

  describe '#call' do
    context 'with valid search query' do
      let(:mock_geocoded_locations) do
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Kaufland Mitte',
            address: 'Alexanderplatz 1, Berlin',
            type: 'shop'
          }
        ]
      end

      let(:mock_matching_points) do
        [
          {
            id: 1,
            timestamp: 1711814700,
            coordinates: [52.5201, 13.4051],
            distance_meters: 45.5,
            date: '2024-03-20T18:45:00Z'
          }
        ]
      end

      let(:mock_visits) do
        [
          {
            timestamp: 1711814700,
            date: '2024-03-20T18:45:00Z',
            coordinates: [52.5201, 13.4051],
            distance_meters: 45.5,
            duration_estimate: '~25m',
            points_count: 1
          }
        ]
      end

      before do
        allow_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).and_return(mock_geocoded_locations)
        
        allow_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near).and_return(mock_matching_points)
        
        allow_any_instance_of(LocationSearch::ResultAggregator)
          .to receive(:group_points_into_visits).and_return(mock_visits)
      end

      it 'returns search results with location data' do
        result = service.call

        expect(result[:query]).to eq('Kaufland')
        expect(result[:locations]).to be_an(Array)
        expect(result[:locations].first).to include(
          place_name: 'Kaufland Mitte',
          coordinates: [52.5200, 13.4050],
          address: 'Alexanderplatz 1, Berlin',
          total_visits: 1
        )
      end

      it 'includes search metadata' do
        result = service.call

        expect(result[:search_metadata]).to include(
          :geocoding_provider,
          :candidates_found,
          :search_time_ms
        )
        expect(result[:search_metadata][:candidates_found]).to eq(1)
      end

      it 'calls geocoding service with the query' do
        expect_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).with('Kaufland')

        service.call
      end

      it 'calls spatial matcher with correct parameters' do
        expect_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near)
          .with(user, 52.5200, 13.4050, 75, { date_from: nil, date_to: nil })

        service.call
      end

      it 'determines appropriate search radius for shop type' do
        expect_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near)
          .with(user, anything, anything, 75, anything)

        service.call
      end

      context 'with different place types' do
        it 'uses smaller radius for street addresses' do
          mock_geocoded_locations[0][:type] = 'street'
          
          expect_any_instance_of(LocationSearch::SpatialMatcher)
            .to receive(:find_points_near)
            .with(user, anything, anything, 50, anything)

          service.call
        end

        it 'uses larger radius for neighborhoods' do
          mock_geocoded_locations[0][:type] = 'neighborhood'
          
          expect_any_instance_of(LocationSearch::SpatialMatcher)
            .to receive(:find_points_near)
            .with(user, anything, anything, 300, anything)

          service.call
        end

        it 'uses custom radius when override provided' do
          service = described_class.new(user, search_params.merge(radius_override: 150))
          
          expect_any_instance_of(LocationSearch::SpatialMatcher)
            .to receive(:find_points_near)
            .with(user, anything, anything, 150, anything)

          service.call
        end
      end

      context 'with date filtering' do
        let(:search_params) do
          {
            query: 'Kaufland',
            date_from: Date.parse('2024-01-01'),
            date_to: Date.parse('2024-03-31')
          }
        end

        it 'passes date filters to spatial matcher' do
          expect_any_instance_of(LocationSearch::SpatialMatcher)
            .to receive(:find_points_near)
            .with(user, anything, anything, anything, {
              date_from: Date.parse('2024-01-01'),
              date_to: Date.parse('2024-03-31')
            })

          service.call
        end
      end
    end

    context 'when no geocoding results found' do
      before do
        allow_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).and_return([])
      end

      it 'returns empty result' do
        result = service.call

        expect(result[:locations]).to be_empty
        expect(result[:total_locations]).to eq(0)
      end
    end

    context 'when no matching points found' do
      before do
        allow_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).and_return([{ lat: 52.5200, lon: 13.4050, name: 'Test' }])
        
        allow_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near).and_return([])
      end

      it 'excludes locations with no visits' do
        result = service.call

        expect(result[:locations]).to be_empty
        expect(result[:total_locations]).to eq(0)
      end
    end

    context 'with blank query' do
      let(:search_params) { { query: '' } }

      it 'returns empty result without calling services' do
        expect(LocationSearch::GeocodingService).not_to receive(:new)

        result = service.call
        
        expect(result[:locations]).to be_empty
      end
    end

    context 'with limit parameter' do
      let(:search_params) { { query: 'Kaufland', limit: 10 } }
      let(:many_visits) { Array.new(15) { |i| { timestamp: i, date: "2024-01-#{i+1}T12:00:00Z" } } }

      before do
        allow_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).and_return([{ lat: 52.5200, lon: 13.4050, name: 'Test' }])
        
        allow_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near).and_return([{}])
        
        allow_any_instance_of(LocationSearch::ResultAggregator)
          .to receive(:group_points_into_visits).and_return(many_visits)
      end

      it 'limits the number of visits returned' do
        result = service.call

        expect(result[:locations].first[:visits].length).to eq(10)
      end
    end
  end
end
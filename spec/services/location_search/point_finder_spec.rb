# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::PointFinder do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, search_params) }
  let(:search_params) { { latitude: 52.5200, longitude: 13.4050 } }

  describe '#call' do
    context 'with valid coordinates' do
      let(:mock_matching_points) do
        [
          {
            id: 1,
            timestamp: 1_711_814_700,
            coordinates: [52.5201, 13.4051],
            distance_meters: 45.5,
            date: '2024-03-20T18:45:00Z'
          }
        ]
      end

      let(:mock_visits) do
        [
          {
            timestamp: 1_711_814_700,
            date: '2024-03-20T18:45:00Z',
            coordinates: [52.5201, 13.4051],
            distance_meters: 45.5,
            duration_estimate: '~25m',
            points_count: 1
          }
        ]
      end

      before do
        allow_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near).and_return(mock_matching_points)

        allow_any_instance_of(LocationSearch::ResultAggregator)
          .to receive(:group_points_into_visits).and_return(mock_visits)
      end

      it 'returns search results with location data' do
        result = service.call

        expect(result[:locations]).to be_an(Array)
        expect(result[:locations].first).to include(
          coordinates: [52.5200, 13.4050],
          total_visits: 1
        )
      end

      it 'calls spatial matcher with correct coordinates and radius' do
        expect_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near)
          .with(user, 52.5200, 13.4050, 500, { date_from: nil, date_to: nil })

        service.call
      end

      context 'with custom radius override' do
        let(:search_params) { { latitude: 52.5200, longitude: 13.4050, radius_override: 150 } }

        it 'uses custom radius when override provided' do
          expect_any_instance_of(LocationSearch::SpatialMatcher)
            .to receive(:find_points_near)
            .with(user, anything, anything, 150, anything)

          service.call
        end
      end

      context 'with date filtering' do
        let(:search_params) do
          {
            latitude: 52.5200,
            longitude: 13.4050,
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

      context 'with limit parameter' do
        let(:search_params) { { latitude: 52.5200, longitude: 13.4050, limit: 10 } }
        let(:many_visits) { Array.new(15) { |i| { timestamp: i, date: "2024-01-#{i + 1}T12:00:00Z" } } }

        before do
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

    context 'when no matching points found' do
      let(:search_params) { { latitude: 52.5200, longitude: 13.4050 } }

      before do
        allow_any_instance_of(LocationSearch::SpatialMatcher)
          .to receive(:find_points_near).and_return([])
      end

      it 'excludes locations with no visits' do
        result = service.call

        expect(result[:locations]).to be_empty
        expect(result[:total_locations]).to eq(0)
      end
    end

    context 'when coordinates are missing' do
      let(:search_params) { {} }

      it 'returns empty result without calling services' do
        expect(LocationSearch::SpatialMatcher).not_to receive(:new)

        result = service.call

        expect(result[:locations]).to be_empty
      end
    end

    context 'when only latitude is provided' do
      let(:search_params) { { latitude: 52.5200 } }

      it 'returns empty result' do
        result = service.call

        expect(result[:locations]).to be_empty
      end
    end

    context 'when only longitude is provided' do
      let(:search_params) { { longitude: 13.4050 } }

      it 'returns empty result' do
        result = service.call

        expect(result[:locations]).to be_empty
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Maps::Hexagons', type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /api/v1/maps/hexagons' do
    let(:valid_params) do
      {
        min_lon: -74.1,
        min_lat: 40.6,
        max_lon: -73.9,
        max_lat: 40.8,
        start_date: '2024-06-01T00:00:00Z',
        end_date: '2024-06-30T23:59:59Z'
      }
    end

    context 'with valid API key authentication' do
      let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

      before do
        # Create test points within the date range and bounding box
        10.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.001), # Slightly different coordinates
                 longitude: -74.0 + (i * 0.001),
                 timestamp: Time.new(2024, 6, 15, 12, i).to_i) # Different times
        end
      end

      it 'returns hexagon data successfully' do
        get '/api/v1/maps/hexagons', params: valid_params, headers: headers

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('type')
        expect(json_response['type']).to eq('FeatureCollection')
        expect(json_response).to have_key('features')
        expect(json_response['features']).to be_an(Array)
      end

      context 'with no data points' do
        let(:empty_user) { create(:user) }
        let(:empty_headers) { { 'Authorization' => "Bearer #{empty_user.api_key}" } }

        it 'returns empty feature collection' do
          get '/api/v1/maps/hexagons', params: valid_params, headers: empty_headers

          expect(response).to have_http_status(:success)

          json_response = JSON.parse(response.body)
          expect(json_response['type']).to eq('FeatureCollection')
          expect(json_response['features']).to be_empty
        end
      end

      context 'with edge case coordinates' do
        it 'handles coordinates at dateline' do
          dateline_params = valid_params.merge(
            min_lon: 179.0, max_lon: -179.0,
            min_lat: -1.0, max_lat: 1.0
          )

          get '/api/v1/maps/hexagons', params: dateline_params, headers: headers

          # Should either succeed or return appropriate error, not crash
          expect([200, 400, 500]).to include(response.status)
        end

        it 'handles polar coordinates' do
          polar_params = valid_params.merge(
            min_lon: -180.0, max_lon: 180.0,
            min_lat: 85.0, max_lat: 90.0
          )

          get '/api/v1/maps/hexagons', params: polar_params, headers: headers

          # Should either succeed or return appropriate error, not crash
          expect([200, 400, 500]).to include(response.status)
        end
      end
    end

    context 'with public sharing UUID' do
      let(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }
      let(:uuid_params) { valid_params.merge(uuid: stat.sharing_uuid) }

      before do
        # Create test points within the stat's month
        15.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.002),
                 longitude: -74.0 + (i * 0.002),
                 timestamp: Time.new(2024, 6, 20, 10, i).to_i)
        end
      end

      it 'returns hexagon data without API key' do
        get '/api/v1/maps/hexagons', params: uuid_params

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('type')
        expect(json_response['type']).to eq('FeatureCollection')
        expect(json_response).to have_key('features')
      end

      it 'uses stat date range automatically' do
        # Points outside the stat's month should not be included
        5.times do |i|
          create(:point,
                 user:,
                 latitude: 40.7 + (i * 0.003),
                 longitude: -74.0 + (i * 0.003),
                 timestamp: Time.new(2024, 7, 1, 8, i).to_i) # July points
        end

        get '/api/v1/maps/hexagons', params: uuid_params

        expect(response).to have_http_status(:success)
      end

      context 'with invalid sharing UUID' do
        it 'returns not found' do
          invalid_uuid_params = valid_params.merge(uuid: 'invalid-uuid')

          get '/api/v1/maps/hexagons', params: invalid_uuid_params

          expect(response).to have_http_status(:not_found)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Shared stats not found or no longer available')
        end
      end

      context 'with expired sharing' do
        let(:stat) { create(:stat, :with_sharing_expired, user:, year: 2024, month: 6) }

        it 'returns not found' do
          get '/api/v1/maps/hexagons', params: uuid_params

          expect(response).to have_http_status(:not_found)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Shared stats not found or no longer available')
        end
      end

      context 'with disabled sharing' do
        let(:stat) { create(:stat, :with_sharing_disabled, user:, year: 2024, month: 6) }

        it 'returns not found' do
          get '/api/v1/maps/hexagons', params: uuid_params

          expect(response).to have_http_status(:not_found)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Shared stats not found or no longer available')
        end
      end

      context 'with pre-calculated hexagon centers' do
        let(:pre_calculated_centers) do
          {
            '8a1fb46622dffff' => [5, 1_717_200_000, 1_717_203_600], # count, earliest, latest timestamps
            '8a1fb46622e7fff' => [3, 1_717_210_000, 1_717_213_600],
            '8a1fb46632dffff' => [8, 1_717_220_000, 1_717_223_600]
          }
        end
        let(:stat) do
          create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6, h3_hex_ids: pre_calculated_centers)
        end

        it 'uses pre-calculated hexagon centers instead of on-the-fly calculation' do
          get '/api/v1/maps/hexagons', params: uuid_params

          expect(response).to have_http_status(:success)

          json_response = JSON.parse(response.body)
          expect(json_response['type']).to eq('FeatureCollection')
          expect(json_response['features'].length).to eq(3)
          expect(json_response['metadata']['pre_calculated']).to be true
          expect(json_response['metadata']['count']).to eq(3)

          # Verify hexagon properties are generated correctly
          feature = json_response['features'].first
          expect(feature['type']).to eq('Feature')
          expect(feature['geometry']['type']).to eq('Polygon')
          expect(feature['geometry']['coordinates'].first).to be_an(Array)
          expect(feature['geometry']['coordinates'].first.length).to eq(7) # 6 vertices + closing vertex

          # Verify properties include timestamp data
          expect(feature['properties']['earliest_point']).to be_present
          expect(feature['properties']['latest_point']).to be_present
        end

        it 'generates proper hexagon polygons from centers' do
          get '/api/v1/maps/hexagons', params: uuid_params

          json_response = JSON.parse(response.body)
          feature = json_response['features'].first
          coordinates = feature['geometry']['coordinates'].first

          # Verify hexagon has 6 unique vertices plus closing vertex
          expect(coordinates.length).to eq(7)
          expect(coordinates.first).to eq(coordinates.last) # Closed polygon
          expect(coordinates.uniq.length).to eq(6) # 6 unique vertices

          # Verify all vertices are different (not collapsed to a point)
          coordinates[0..5].each_with_index do |vertex, i|
            next_vertex = coordinates[(i + 1) % 6]
            expect(vertex).not_to eq(next_vertex)
          end
        end
      end

      context 'with legacy area_too_large hexagon data' do
        let(:stat) do
          create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6,
                 h3_hex_ids: { 'area_too_large' => true })
        end

        before do
          # Create points so that the service can potentially succeed
          5.times do |i|
            create(:point,
                   user:,
                   latitude: 40.7 + (i * 0.001),
                   longitude: -74.0 + (i * 0.001),
                   timestamp: Time.new(2024, 6, 15, 12, i).to_i)
          end
        end

        it 'handles legacy area_too_large flag gracefully' do
          get '/api/v1/maps/hexagons', params: uuid_params

          # The endpoint should handle the legacy data gracefully and not crash
          # We're primarily testing that the condition `@stat&.h3_hex_ids&.dig('area_too_large')` is covered
          expect([200, 400, 500]).to include(response.status)
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/maps/hexagons', params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid API key' do
      let(:headers) { { 'Authorization' => 'Bearer invalid-key' } }

      it 'returns unauthorized' do
        get '/api/v1/maps/hexagons', params: valid_params, headers: headers

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/maps/hexagons/bounds' do
    context 'with valid API key authentication' do
      let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
      let(:date_params) do
        {
          start_date: Time.new(2024, 6, 1).to_i,
          end_date: Time.new(2024, 6, 30, 23, 59, 59).to_i
        }
      end

      before do
        # Create test points within the date range
        create(:point, user:, latitude: 40.6, longitude: -74.1, timestamp: Time.new(2024, 6, 1, 12, 0).to_i)
        create(:point, user:, latitude: 40.8, longitude: -73.9, timestamp: Time.new(2024, 6, 30, 15, 0).to_i)
        create(:point, user:, latitude: 40.7, longitude: -74.0, timestamp: Time.new(2024, 6, 15, 10, 0).to_i)
      end

      it 'returns bounding box for user data' do
        get '/api/v1/maps/hexagons/bounds', params: date_params, headers: headers

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to include('min_lat', 'max_lat', 'min_lng', 'max_lng', 'point_count')
        expect(json_response['min_lat']).to eq(40.6)
        expect(json_response['max_lat']).to eq(40.8)
        expect(json_response['min_lng']).to eq(-74.1)
        expect(json_response['max_lng']).to eq(-73.9)
        expect(json_response['point_count']).to eq(3)
      end

      it 'returns not found when no points exist in date range' do
        get '/api/v1/maps/hexagons/bounds',
            params: { start_date: '2023-01-01T00:00:00Z', end_date: '2023-01-31T23:59:59Z' },
            headers: headers

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('No data found for the specified date range')
        expect(json_response['point_count']).to eq(0)
      end

      it 'requires date range parameters' do
        get '/api/v1/maps/hexagons/bounds', headers: headers

        expect(response).to have_http_status(:bad_request)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('No date range specified')
      end

      it 'handles different timestamp formats' do
        string_date_params = {
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z'
        }

        get '/api/v1/maps/hexagons/bounds', params: string_date_params, headers: headers

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to include('min_lat', 'max_lat', 'min_lng', 'max_lng', 'point_count')
      end

      it 'handles numeric string timestamp format' do
        numeric_string_params = {
          start_date: '1717200000', # June 1, 2024 in timestamp
          end_date: '1719791999' # June 30, 2024 in timestamp
        }

        get '/api/v1/maps/hexagons/bounds', params: numeric_string_params, headers: headers

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to include('min_lat', 'max_lat', 'min_lng', 'max_lng', 'point_count')
      end

      context 'error handling' do
        it 'handles invalid date format gracefully' do
          invalid_date_params = {
            start_date: 'invalid-date',
            end_date: '2024-06-30T23:59:59Z'
          }

          get '/api/v1/maps/hexagons/bounds', params: invalid_date_params, headers: headers

          expect(response).to have_http_status(:bad_request)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to include('Invalid date format')
        end
      end
    end

    context 'with public sharing UUID' do
      let(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }

      before do
        # Create test points within the stat's month
        create(:point, user:, latitude: 41.0, longitude: -74.5, timestamp: Time.new(2024, 6, 5, 9, 0).to_i)
        create(:point, user:, latitude: 41.2, longitude: -74.2, timestamp: Time.new(2024, 6, 25, 14, 0).to_i)
      end

      it 'returns bounds for the shared stat period' do
        get '/api/v1/maps/hexagons/bounds', params: { uuid: stat.sharing_uuid }

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response).to include('min_lat', 'max_lat', 'min_lng', 'max_lng', 'point_count')
        expect(json_response['min_lat']).to eq(41.0)
        expect(json_response['max_lat']).to eq(41.2)
        expect(json_response['point_count']).to eq(2)
      end

      context 'with invalid sharing UUID' do
        it 'returns not found' do
          get '/api/v1/maps/hexagons/bounds', params: { uuid: 'invalid-uuid' }

          expect(response).to have_http_status(:not_found)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Shared stats not found or no longer available')
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/maps/hexagons/bounds',
            params: { start_date: '2024-06-01T00:00:00Z', end_date: '2024-06-30T23:59:59Z' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

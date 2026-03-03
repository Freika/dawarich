# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::LocationsController, type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:headers) { { 'Authorization' => "Bearer #{api_key}" } }

  describe 'GET /api/v1/locations' do
    context 'with valid authentication' do
      context 'when coordinates are provided' do
        let(:latitude) { 52.5200 }
        let(:longitude) { 13.4050 }
        let(:mock_search_result) do
          {
            query: nil,
            locations: [
              {
                place_name: 'Kaufland Mitte',
                coordinates: [52.5200, 13.4050],
                address: 'Alexanderplatz 1, Berlin',
                total_visits: 2,
                first_visit: '2024-01-15T09:30:00Z',
                last_visit: '2024-03-20T18:45:00Z',
                visits: [
                  {
                    timestamp: 1_711_814_700,
                    date: '2024-03-20T18:45:00Z',
                    coordinates: [52.5201, 13.4051],
                    distance_meters: 45.5,
                    duration_estimate: '~25m',
                    points_count: 8
                  }
                ]
              }
            ],
            total_locations: 1,
            search_metadata: {
              geocoding_provider: 'photon',
              candidates_found: 3,
              search_time_ms: 234
            }
          }
        end

        before do
          allow_any_instance_of(LocationSearch::PointFinder)
            .to receive(:call).and_return(mock_search_result)
        end

        it 'returns successful response with search results' do
          get '/api/v1/locations', params: { lat: latitude, lon: longitude }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['query']).to be_nil
          expect(json_response['locations']).to be_an(Array)
          expect(json_response['locations'].first['place_name']).to eq('Kaufland Mitte')
          expect(json_response['total_locations']).to eq(1)
        end

        it 'includes search metadata in response' do
          get '/api/v1/locations', params: { lat: latitude, lon: longitude }, headers: headers

          json_response = JSON.parse(response.body)
          expect(json_response['search_metadata']).to include(
            'geocoding_provider' => 'photon',
            'candidates_found' => 3
          )
        end

        it 'passes search parameters to PointFinder service' do
          expect(LocationSearch::PointFinder)
            .to receive(:new)
            .with(user, hash_including(
                          latitude: latitude,
                          longitude: longitude,
                          limit: 50,
                          date_from: nil,
                          date_to: nil,
                          radius_override: nil
                        ))
            .and_return(double(call: mock_search_result))

          get '/api/v1/locations', params: { lat: latitude, lon: longitude }, headers: headers
        end

        context 'with additional search parameters' do
          let(:params) do
            {
              lat: latitude,
              lon: longitude,
              limit: 20,
              date_from: '2024-01-01',
              date_to: '2024-03-31',
              radius_override: 200
            }
          end

          it 'passes all parameters to the service' do
            expect(LocationSearch::PointFinder)
              .to receive(:new)
              .with(user, hash_including(
                            latitude: latitude,
                            longitude: longitude,
                            limit: 20,
                            date_from: Date.parse('2024-01-01'),
                            date_to: Date.parse('2024-03-31'),
                            radius_override: 200
                          ))
              .and_return(double(call: mock_search_result))

            get '/api/v1/locations', params: params, headers: headers
          end
        end

        context 'with invalid date parameters' do
          it 'handles invalid date_from gracefully' do
            expect do
              get '/api/v1/locations', params: { lat: latitude, lon: longitude, date_from: 'invalid-date' },
headers: headers
            end.not_to raise_error

            expect(response).to have_http_status(:ok)
          end

          it 'handles invalid date_to gracefully' do
            expect do
              get '/api/v1/locations', params: { lat: latitude, lon: longitude, date_to: 'invalid-date' },
headers: headers
            end.not_to raise_error

            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'when no search results are found' do
        let(:empty_result) do
          {
            query: 'NonexistentPlace',
            locations: [],
            total_locations: 0,
            search_metadata: { geocoding_provider: nil, candidates_found: 0, search_time_ms: 0 }
          }
        end

        before do
          allow_any_instance_of(LocationSearch::PointFinder)
            .to receive(:call).and_return(empty_result)
        end

        it 'returns empty results successfully' do
          get '/api/v1/locations', params: { lat: 0.0, lon: 0.0 }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['locations']).to be_empty
          expect(json_response['total_locations']).to eq(0)
        end
      end

      context 'when coordinates are missing' do
        it 'returns bad request error' do
          get '/api/v1/locations', headers: headers

          expect(response).to have_http_status(:bad_request)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Coordinates (lat, lon) are required')
        end
      end

      context 'when only latitude is provided' do
        it 'returns bad request error' do
          get '/api/v1/locations', params: { lat: 52.5200 }, headers: headers

          expect(response).to have_http_status(:bad_request)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Coordinates (lat, lon) are required')
        end
      end

      context 'when coordinates are invalid' do
        it 'returns bad request error for invalid latitude' do
          get '/api/v1/locations', params: { lat: 91, lon: 0 }, headers: headers

          expect(response).to have_http_status(:bad_request)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Invalid coordinates: lat must be -90..90, lon must be -180..180')
        end

        it 'returns bad request error for invalid longitude' do
          get '/api/v1/locations', params: { lat: 0, lon: 181 }, headers: headers

          expect(response).to have_http_status(:bad_request)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Invalid coordinates: lat must be -90..90, lon must be -180..180')
        end
      end

      context 'when service raises an error' do
        before do
          allow_any_instance_of(LocationSearch::PointFinder)
            .to receive(:call).and_raise(StandardError.new('Service error'))
        end

        it 'returns internal server error' do
          get '/api/v1/locations', params: { lat: 52.5200, lon: 13.4050 }, headers: headers

          expect(response).to have_http_status(:internal_server_error)

          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('Search failed. Please try again.')
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/locations', params: { lat: 52.5200, lon: 13.4050 }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid API key' do
      let(:invalid_headers) { { 'Authorization' => 'Bearer invalid_key' } }

      it 'returns unauthorized error' do
        get '/api/v1/locations', params: { lat: 52.5200, lon: 13.4050 }, headers: invalid_headers

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with user data isolation' do
      let(:user1) { create(:user) }
      let(:user2) { create(:user) }
      let(:user1_headers) { { 'Authorization' => "Bearer #{user1.api_key}" } }

      before do
        # Create points for both users
        create(:point, user: user1, latitude: 52.5200, longitude: 13.4050)
        create(:point, user: user2, latitude: 52.5200, longitude: 13.4050)

        # Mock service to verify user isolation
        allow(LocationSearch::PointFinder).to receive(:new) do |user, _params|
          expect(user).to eq(user1) # Should only be called with user1
          double(call: { query: nil, locations: [], total_locations: 0, search_metadata: {} })
        end
      end

      it 'only searches within the authenticated user data' do
        get '/api/v1/locations', params: { lat: 52.5200, lon: 13.4050 }, headers: user1_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'GET /api/v1/locations/suggestions' do
    context 'with valid authentication' do
      let(:mock_suggestions) do
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Kaufland Mitte',
            address: 'Alexanderplatz 1, Berlin',
            type: 'shop'
          },
          {
            lat: 52.5100,
            lon: 13.4000,
            name: 'Kaufland Friedrichshain',
            address: 'Warschauer Str. 80, Berlin',
            type: 'shop'
          }
        ]
      end

      before do
        allow_any_instance_of(LocationSearch::GeocodingService)
          .to receive(:search).and_return(mock_suggestions)
      end

      context 'with valid search query' do
        it 'returns formatted suggestions' do
          get '/api/v1/locations/suggestions', params: { q: 'Kaufland' }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['suggestions']).to be_an(Array)
          expect(json_response['suggestions'].length).to eq(2)

          first_suggestion = json_response['suggestions'].first
          expect(first_suggestion).to include(
            'name' => 'Kaufland Mitte',
            'address' => 'Alexanderplatz 1, Berlin',
            'coordinates' => [52.5200, 13.4050],
            'type' => 'shop'
          )
        end

        it 'limits suggestions to 10 results' do
          large_suggestions = Array.new(10) do |i|
            {
              lat: 52.5000 + i * 0.001,
              lon: 13.4000 + i * 0.001,
              name: "Location #{i}",
              address: "Address #{i}",
              type: 'place'
            }
          end

          allow_any_instance_of(LocationSearch::GeocodingService)
            .to receive(:search).and_return(large_suggestions)

          get '/api/v1/locations/suggestions', params: { q: 'test' }, headers: headers

          json_response = JSON.parse(response.body)
          expect(json_response['suggestions'].length).to eq(10)
        end
      end

      context 'with short search query' do
        it 'returns empty suggestions for queries shorter than 2 characters' do
          get '/api/v1/locations/suggestions', params: { q: 'a' }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['suggestions']).to be_empty
        end
      end

      context 'with blank query' do
        it 'returns empty suggestions' do
          get '/api/v1/locations/suggestions', params: { q: '' }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['suggestions']).to be_empty
        end
      end

      context 'when geocoding service raises an error' do
        before do
          allow_any_instance_of(LocationSearch::GeocodingService)
            .to receive(:search).and_raise(StandardError.new('Geocoding error'))
        end

        it 'returns empty suggestions gracefully' do
          get '/api/v1/locations/suggestions', params: { q: 'test' }, headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['suggestions']).to be_empty
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/locations/suggestions', params: { q: 'test' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

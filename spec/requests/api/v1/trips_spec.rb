# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/trips', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /index' do
    let!(:trip) { create(:trip, user: user) }
    let!(:other_trip) { create(:trip) }

    it 'returns trips for the current user only' do
      get api_v1_trips_url, headers: headers

      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json.map { _1['id'] }).to eq([trip.id])
      expect(json.first).to include('name' => trip.name, 'distance_meters' => trip.distance)
      expect(json.first).not_to have_key('path')
    end

    it 'filters by date range' do
      create(:trip, user: user, started_at: 1.year.ago, ended_at: 1.year.ago + 2.days)

      get api_v1_trips_url, headers: headers,
                            params: { start_at: '2024-11-01T00:00:00Z', end_at: '2024-11-30T00:00:00Z' }

      json = JSON.parse(response.body)
      expect(json.map { _1['id'] }).to eq([trip.id])
    end

    it 'returns 422 for an unparseable date' do
      get api_v1_trips_url, headers: headers, params: { start_at: 'not-a-date' }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'treats a non-positive per_page as 1' do
      create(:trip, user: user)

      get api_v1_trips_url, headers: headers, params: { page: 1, per_page: 0 }

      expect(JSON.parse(response.body).length).to eq(1)
      expect(response.headers['X-Total-Pages']).to eq('2')
    end

    it 'paginates when page is given' do
      create(:trip, user: user)

      get api_v1_trips_url, headers: headers, params: { page: 1, per_page: 1 }

      expect(JSON.parse(response.body).length).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
      expect(response.headers['X-Total-Pages']).to eq('2')
    end

    it 'returns 401 without auth' do
      get api_v1_trips_url
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /show' do
    let(:trip) { create(:trip, user: user) }

    it 'returns the trip with its path' do
      get api_v1_trip_url(trip), headers: headers

      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json['id']).to eq(trip.id)
      expect(json['description']).to eq(trip.description.to_plain_text)
      expect(json['path']).to eq([[1.0, 1.0], [2.0, 2.0], [3.0, 3.0]])
    end

    it 'returns 404 for another user trip' do
      get api_v1_trip_url(create(:trip)), headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /create' do
    let(:valid_params) do
      {
        trip: {
          name: 'Summer in Italy',
          started_at: '2025-07-01T08:00:00Z',
          ended_at: '2025-07-14T20:00:00Z',
          description: 'Rome, Florence and Venice'
        }
      }
    end

    it 'creates a trip and enqueues calculation' do
      expect do
        post api_v1_trips_url, params: valid_params, headers: headers, as: :json
      end.to change(user.trips, :count).by(1).and have_enqueued_job(Trips::CalculateAllJob)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['name']).to eq('Summer in Italy')
      expect(json['description']).to eq('Rome, Florence and Venice')
    end

    it 'returns 422 for invalid params' do
      post api_v1_trips_url, headers: headers, as: :json,
                             params: { trip: valid_params[:trip].merge(ended_at: '2025-06-01T00:00:00Z') }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['errors']).to be_present
    end

    it 'returns 401 for an inactive user' do
      user.update!(status: :inactive)

      post api_v1_trips_url, params: valid_params, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /update' do
    let(:trip) { create(:trip, user: user) }

    it 'updates the trip' do
      patch api_v1_trip_url(trip), headers: headers, as: :json,
                                   params: { trip: { name: 'Renamed', description: 'New text' } }

      expect(response).to be_successful
      expect(trip.reload.name).to eq('Renamed')
      expect(trip.description.to_plain_text).to eq('New text')
    end

    it 'returns 422 for invalid params' do
      patch api_v1_trip_url(trip), headers: headers, as: :json, params: { trip: { name: '' } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for another user trip' do
      patch api_v1_trip_url(create(:trip)), headers: headers, as: :json, params: { trip: { name: 'x' } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /destroy' do
    let!(:trip) { create(:trip, user: user) }

    it 'deletes the trip' do
      expect do
        delete api_v1_trip_url(trip), headers: headers
      end.to change(Trip, :count).by(-1)

      expect(response).to be_successful
    end

    it 'returns 404 for another user trip' do
      other = create(:trip)

      expect do
        delete api_v1_trip_url(other), headers: headers
      end.not_to change(Trip, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end

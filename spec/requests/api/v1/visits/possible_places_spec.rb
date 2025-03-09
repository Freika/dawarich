# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Visits::PossiblePlaces', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:visit) { create(:visit, user:) }
  let(:place) { create(:place) }
  let!(:place_visit) { create(:place_visit, visit:, place:) }
  let(:other_user) { create(:user) }
  let(:other_visit) { create(:visit, user: other_user) }

  describe 'GET /api/v1/visits/:id/possible_places' do
    context 'when visit belongs to the user' do
      it 'returns a list of suggested places for the visit' do
        get "/api/v1/visits/#{visit.id}/possible_places", params: { api_key: }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response).to be_an(Array)
        expect(json_response.size).to eq(1)
        expect(json_response.first['id']).to eq(place.id)
      end
    end

    context 'when visit does not exist' do
      it 'returns a not found error' do
        get '/api/v1/visits/999999/possible_places', headers: { 'Authorization' => "Bearer #{api_key}" }

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Visit not found')
      end
    end

    context 'when visit does not belong to the user' do
      it 'returns a not found error' do
        get "/api/v1/visits/#{other_visit.id}/possible_places", params: { api_key: }

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Visit not found')
      end
    end

    context 'when no api key is provided' do
      it 'returns unauthorized error' do
        get "/api/v1/visits/#{visit.id}/possible_places"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TracksController, type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  describe 'GET #index' do
    let!(:track1) { create(:track, user: user, start_at: 2.days.ago, end_at: 2.days.ago + 1.hour) }
    let!(:track2) { create(:track, user: user, start_at: 1.day.ago, end_at: 1.day.ago + 1.hour) }

    it 'returns tracks for the user' do
      get "/api/v1/tracks", params: { api_key: api_key }

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['tracks']).to be_an(Array)
      expect(json_response['tracks'].size).to eq(2)

      track_ids = json_response['tracks'].map { |t| t['id'] }
      expect(track_ids).to include(track1.id, track2.id)
    end

    it 'filters tracks by date range' do
      start_at = 1.day.ago.beginning_of_day.iso8601
      end_at = 1.day.ago.end_of_day.iso8601

      get "/api/v1/tracks", params: {
        api_key: api_key,
        start_at: start_at,
        end_at: end_at
      }

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['tracks'].size).to eq(1)
      expect(json_response['tracks'].first['id']).to eq(track2.id)
    end

    it 'requires authentication' do
      get "/api/v1/tracks"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST #create' do
    it 'triggers track generation' do
      expect {
        post "/api/v1/tracks", params: { api_key: api_key }
      }.to have_enqueued_job(Tracks::CreateJob).with(user.id)

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Track generation started')
    end

    it 'requires authentication' do
      post "/api/v1/tracks"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/tracks/:track_id/points', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:track) { create(:track, user: user) }

  describe 'GET /index' do
    let!(:point1) { create(:point, user: user, track: track, timestamp: 1.hour.ago.to_i) }
    let!(:point2) { create(:point, user: user, track: track, timestamp: 30.minutes.ago.to_i) }
    let!(:point3) { create(:point, user: user, track: track, timestamp: 15.minutes.ago.to_i) }
    let!(:other_track_point) { create(:point, user: user, timestamp: 10.minutes.ago.to_i) }

    it 'returns successful response' do
      get api_v1_track_points_url(track), headers: headers
      expect(response).to be_successful
    end

    it 'returns points belonging to the track' do
      get api_v1_track_points_url(track), headers: headers
      json = JSON.parse(response.body)

      expect(json.length).to eq(3)
      point_ids = json.map { |p| p['id'] }
      expect(point_ids).to contain_exactly(point1.id, point2.id, point3.id)
    end

    it 'does not return points from other tracks' do
      get api_v1_track_points_url(track), headers: headers
      json = JSON.parse(response.body)

      point_ids = json.map { |p| p['id'] }
      expect(point_ids).not_to include(other_track_point.id)
    end

    it 'orders points by timestamp ascending' do
      get api_v1_track_points_url(track), headers: headers
      json = JSON.parse(response.body)

      expect(json.first['id']).to eq(point1.id)
      expect(json.second['id']).to eq(point2.id)
      expect(json.third['id']).to eq(point3.id)
    end

    it 'serializes points using Api::PointSerializer' do
      get api_v1_track_points_url(track), headers: headers
      json = JSON.parse(response.body)

      point_data = json.first
      expect(point_data).to include('id', 'latitude', 'longitude', 'timestamp')
      expect(point_data).not_to include('raw_data', 'user_id', 'import_id')
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_track_points_url(track)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when track belongs to another user' do
      let(:other_user) { create(:user) }
      let(:other_track) { create(:track, user: other_user) }

      it 'returns not found' do
        get api_v1_track_points_url(other_track), headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when track does not exist' do
      it 'returns not found' do
        get api_v1_track_points_url(id: -1, track_id: -1), headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when track has no points' do
      let(:empty_track) { create(:track, user: user) }

      it 'returns empty array' do
        get api_v1_track_points_url(empty_track), headers: headers
        json = JSON.parse(response.body)

        expect(json).to eq([])
      end
    end
  end
end

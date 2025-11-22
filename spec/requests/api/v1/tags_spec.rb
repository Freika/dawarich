# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tags', type: :request do
  let(:user) { create(:user) }
  let(:tag) { create(:tag, user: user, name: 'Home', icon: '🏠', color: '#4CAF50', privacy_radius_meters: 500) }
  let!(:place) { create(:place, name: 'My Place', latitude: 10.0, longitude: 20.0) }

  before do
    tag.places << place
  end

  describe 'GET /api/v1/tags/privacy_zones' do
    context 'when authenticated' do
      before do
        user.create_api_key unless user.api_key.present?
        get privacy_zones_api_v1_tags_path, params: { api_key: user.api_key }
      end

      it 'returns success' do
        expect(response).to be_successful
      end

      it 'returns the correct JSON structure' do
        json_response = JSON.parse(response.body)
        expect(json_response).to be_an(Array)
        expect(json_response.first).to include(
          'tag_id' => tag.id,
          'tag_name' => 'Home',
          'tag_icon' => '🏠',
          'tag_color' => '#4CAF50',
          'radius_meters' => 500
        )
        expect(json_response.first['places']).to be_an(Array)
        expect(json_response.first['places'].first).to include(
          'id' => place.id,
          'name' => 'My Place',
          'latitude' => 10.0,
          'longitude' => 20.0
        )
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get privacy_zones_api_v1_tags_path
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

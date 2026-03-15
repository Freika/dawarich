# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Locations', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:user_membership) { create(:family_membership, user: user, family: family, role: :owner) }

  describe 'GET /api/v1/families/locations' do
    context 'with valid API key' do
      before do
        create(:family_membership, user: other_user, family: family, role: :member)
        other_user.update_family_location_sharing!(true, duration: 'permanent')
      end

      it 'returns family member locations' do
        get '/api/v1/families/locations', params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('locations')
        expect(json_response).to have_key('updated_at')
        expect(json_response).to have_key('sharing_enabled')
      end

      it 'includes sharing status' do
        user.update_family_location_sharing!(true, duration: 'permanent')

        get '/api/v1/families/locations', params: { api_key: user.api_key }

        json_response = JSON.parse(response.body)
        expect(json_response['sharing_enabled']).to be true
      end
    end

    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations', params: { api_key: 'invalid' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is not in a family' do
      let(:solo_user) { create(:user) }

      it 'returns forbidden' do
        get '/api/v1/families/locations', params: { api_key: solo_user.api_key }

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('User is not part of a family')
      end
    end
  end

  describe 'GET /api/v1/families/locations/history' do
    let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }

    before do
      travel_to(now)
      create(:family_membership, user: other_user, family: family, role: :member)
      other_user.update_family_location_sharing!(true, duration: 'permanent')
      other_user.update!(
        settings: other_user.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 1.week.ago.iso8601 } }
        )
      )
    end

    after { travel_back }

    context 'with valid params' do
      it 'returns history points for sharing members' do
        create(:point, user: other_user, timestamp: 3.hours.ago.to_i)
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        get '/api/v1/families/locations/history',
            params: { api_key: user.api_key, start_at: 1.day.ago.iso8601, end_at: Time.current.iso8601 }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['members']).to be_an(Array)
        expect(json['members'].length).to eq(1)
        expect(json['members'].first['points'].length).to eq(2)
        expect(json['members'].first['sharing_since']).to be_present
      end
    end

    context 'without start_at or end_at' do
      it 'returns bad request' do
        get '/api/v1/families/locations/history',
            params: { api_key: user.api_key }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations/history',
            params: { start_at: 1.day.ago.iso8601, end_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when no members are sharing' do
      before { other_user.update_family_location_sharing!(false) }

      it 'returns empty members array' do
        get '/api/v1/families/locations/history',
            params: { api_key: user.api_key, start_at: 1.day.ago.iso8601, end_at: Time.current.iso8601 }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['members']).to eq([])
      end
    end
  end
end

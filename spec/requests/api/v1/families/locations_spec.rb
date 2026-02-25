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
end

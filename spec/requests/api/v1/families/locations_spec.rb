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

  describe 'PATCH /api/v1/families/locations/toggle' do
    before { sign_in user }

    context 'with valid session authentication' do
      context 'when enabling location sharing' do
        around do |example|
          travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) { example.run }
        end

        it 'enables location sharing with duration' do
          patch '/api/v1/families/locations/toggle',
                params: { enabled: true, duration: '1h' },
                as: :json

          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['enabled']).to be true
          expect(json_response['duration']).to eq('1h')
          expect(json_response['message']).to eq('Location sharing enabled for 1 hour')
          expect(json_response['expires_at']).to eq(1.hour.from_now.iso8601)
        end

        it 'enables location sharing permanently' do
          patch '/api/v1/families/locations/toggle',
                params: { enabled: true, duration: 'permanent' },
                as: :json

          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['enabled']).to be true
          expect(json_response['duration']).to eq('permanent')
          expect(json_response).not_to have_key('expires_at')
        end
      end

      context 'when disabling location sharing' do
        before do
          user.update_family_location_sharing!(true, duration: '1h')
        end

        it 'disables location sharing' do
          patch '/api/v1/families/locations/toggle',
                params: { enabled: false },
                as: :json

          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['enabled']).to be false
          expect(json_response['message']).to eq('Location sharing disabled')
        end
      end

      context 'when user is not in a family' do
        let(:solo_user) { create(:user) }

        before do
          sign_out user
          sign_in solo_user
        end

        it 'returns forbidden' do
          patch '/api/v1/families/locations/toggle',
                params: { enabled: true, duration: '1h' },
                as: :json

          expect(response).to have_http_status(:forbidden)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('User is not part of a family')
        end
      end

      context 'when update fails' do
        before do
          allow_any_instance_of(User).to receive(:update_family_location_sharing!)
            .and_raise(StandardError, 'Database error')
        end

        it 'returns internal server error' do
          patch '/api/v1/families/locations/toggle',
                params: { enabled: true, duration: '1h' },
                as: :json

          expect(response).to have_http_status(:internal_server_error)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be false
          expect(json_response['message']).to eq('An error occurred while updating location sharing')
        end
      end
    end

    context 'without authentication' do
      before { sign_out user }

      it 'returns unauthorized' do
        patch '/api/v1/families/locations/toggle',
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

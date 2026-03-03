# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family::LocationSharing', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:user_membership) { create(:family_membership, user: user, family: family, role: :owner) }

  before { sign_in user }

  describe 'PATCH /family/location_sharing' do
    context 'when enabling location sharing' do
      around do |example|
        travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) { example.run }
      end

      it 'enables location sharing with duration' do
        patch '/family/location_sharing',
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['enabled']).to be true
        expect(json_response['duration']).to eq('1h')
        expect(json_response['message']).to eq('Location sharing enabled for 1 hour')
        expect(json_response['expires_at']).to eq(1.hour.from_now.utc.iso8601)
      end

      it 'enables location sharing permanently' do
        patch '/family/location_sharing',
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
        patch '/family/location_sharing',
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
        patch '/family/location_sharing',
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
        patch '/family/location_sharing',
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('An error occurred while updating location sharing')
      end
    end

    context 'without authentication' do
      before { sign_out user }

      it 'returns unauthorized' do
        patch '/family/location_sharing',
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('You need to sign in or sign up before continuing.')
      end
    end

    context 'with turbo_stream format' do
      it 'enables sharing with duration and returns turbo_stream' do
        patch '/family/location_sharing',
              params: { enabled: true, duration: '1h' },
              as: :turbo_stream

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "location-sharing-#{user.id}")
        expect_flash_stream('Location sharing enabled for 1 hour')
      end

      it 'enables sharing permanently and returns turbo_stream' do
        patch '/family/location_sharing',
              params: { enabled: true, duration: 'permanent' },
              as: :turbo_stream

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "location-sharing-#{user.id}")
      end

      it 'disables sharing and returns turbo_stream with flash' do
        user.update_family_location_sharing!(true, duration: '1h')

        patch '/family/location_sharing',
              params: { enabled: false },
              as: :turbo_stream

        expect_turbo_stream_response
        expect_turbo_stream_action('replace', "location-sharing-#{user.id}")
        expect_flash_stream('Location sharing disabled')
      end

      it 'returns turbo_stream flash error when user is not in a family' do
        solo_user = create(:user)
        sign_out user
        sign_in solo_user

        patch '/family/location_sharing',
              params: { enabled: true, duration: '1h' },
              as: :turbo_stream

        expect(response).to have_http_status(:forbidden)
        expect_turbo_stream_response
        expect_flash_stream('User is not part of a family')
      end
    end
  end
end

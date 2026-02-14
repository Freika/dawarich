# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::RefreshToken do
  describe '#call' do
    subject(:service) { described_class.new(user) }

    let(:user) do
      create(:user, settings: {
               'google_photos_access_token' => 'old_access_token',
               'google_photos_refresh_token' => 'refresh_token_123',
               'google_photos_token_expires_at' => expires_at
             })
    end

    context 'when no refresh token is available' do
      let(:user) { create(:user, settings: {}) }

      it 'returns error' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No refresh token available')
      end
    end

    context 'when token is not expired' do
      let(:expires_at) { 1.hour.from_now.to_i }

      it 'returns current access token' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:access_token]).to eq('old_access_token')
      end
    end

    context 'when token is expired' do
      let(:expires_at) { 1.minute.ago.to_i }

      before do
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(
            status: 200,
            body: {
              access_token: 'new_access_token',
              expires_in: 3600
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'refreshes the token' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:access_token]).to eq('new_access_token')
      end

      it 'saves new token to user settings' do
        service.call

        user.reload
        expect(user.settings['google_photos_access_token']).to eq('new_access_token')
      end
    end

    context 'when token expires within 5 minutes' do
      let(:expires_at) { 3.minutes.from_now.to_i }

      before do
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(
            status: 200,
            body: {
              access_token: 'new_access_token',
              expires_in: 3600
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'proactively refreshes the token' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:access_token]).to eq('new_access_token')
      end
    end

    context 'when refresh fails with invalid token' do
      let(:expires_at) { 1.minute.ago.to_i }

      before do
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(status: 400, body: '{"error": "invalid_grant"}')
      end

      it 'returns error and clears tokens' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to include('Refresh token invalid')

        user.reload
        expect(user.settings['google_photos_access_token']).to be_nil
        expect(user.settings['google_photos_refresh_token']).to be_nil
      end
    end
  end
end

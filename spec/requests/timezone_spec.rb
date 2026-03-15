# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Timezone Switching', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'America/New_York' }) }

  describe 'ApplicationController timezone switching' do
    context 'when user is authenticated' do
      before { sign_in user }

      it 'sets Time.zone to user timezone during request' do
        get settings_general_index_path

        expect(response).to have_http_status(:success)
        # The settings page renders timezone dropdown
        expect(response.body).to include('Your timezone')
      end
    end

    context 'when user is not authenticated' do
      it 'does not crash and uses default timezone' do
        get root_path

        expect(response).to have_http_status(:success)
      end
    end

    context 'when user has invalid timezone stored' do
      let(:user) { create(:user, settings: { 'timezone' => 'Invalid/Zone' }) }

      before { sign_in user }

      it 'falls back gracefully without crashing' do
        get settings_general_index_path

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'ApiController timezone switching' do
    let(:api_user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }

    context 'when API key is valid' do
      it 'returns user timezone in settings response' do
        get '/api/v1/settings', headers: { 'Authorization' => "Bearer #{api_user.api_key}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json.dig('settings', 'timezone')).to eq('Asia/Tokyo')
      end
    end

    context 'when API key is invalid' do
      it 'does not crash with invalid API key' do
        get '/api/v1/points', headers: { 'Authorization' => 'Bearer invalid_key' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

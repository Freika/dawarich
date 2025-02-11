# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/maps', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'when user is authenticated' do
    let!(:user) { create(:user) }

    before do
      sign_in user
    end

    describe 'GET /index' do
      it 'returns a success response' do
        get settings_maps_url

        expect(response).to be_successful
      end
    end

    describe 'PATCH /update' do
      it 'returns a success response' do
        patch settings_maps_path, params: { maps: { name: 'Test', url: 'https://test.com' } }

        expect(response).to redirect_to(settings_maps_path)
        expect(user.settings['maps']).to eq({ 'name' => 'Test', 'url' => 'https://test.com' })
      end
    end
  end

  context 'when user is not authenticated' do
    it 'redirects to the sign in page' do
      get settings_maps_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

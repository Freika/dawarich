# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings', type: :request do
  describe 'GET /theme' do
    let(:params) { { theme: 'light' } }

    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'updates the user theme' do
        get '/settings/theme', params: params
        expect(user.reload.theme).to eq('light')
      end

      it 'redirects to the root path' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(root_path)
      end

      context 'when theme is dark' do
        let(:params) { { theme: 'dark' } }

        it 'updates the user theme' do
          get '/settings/theme', params: params
          expect(user.reload.theme).to eq('dark')
        end
      end
    end
  end

  describe 'POST /generate_api_key' do
    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'generates an API key for the user' do
        expect { post '/settings/generate_api_key' }.to(change { user.reload.api_key })
      end

      it 'redirects back' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'PATCH /settings' do
    let(:user) { create(:user) }
    let(:params) { { settings: { 'meters_between_routes' => '1000', 'minutes_between_routes' => '10' } } }

    before do
      sign_in user
    end

    it 'updates the user settings' do
      patch '/settings', params: params

      user.reload
      expect(user.settings['meters_between_routes']).to eq('1000')
      expect(user.settings['minutes_between_routes']).to eq('10')
    end

    it 'refreshes cached photos when requested' do
      Rails.cache.write("photos_#{user.id}_test", ['cached'])
      Rails.cache.write("photo_thumbnail_#{user.id}_immich_test", 'thumb')

      patch '/settings', params: params.merge(refresh_photos_cache: '1')

      expect(Rails.cache.read("photos_#{user.id}_test")).to be_nil
      expect(Rails.cache.read("photo_thumbnail_#{user.id}_immich_test")).to be_nil
    end

    context 'when immich settings change' do
      let(:immich_url) { 'https://immich.test' }
      let(:immich_api_key) { 'immich-key' }
      let(:immich_response) do
        { 'assets' => { 'items' => [{ 'id' => 'asset-id' }] } }.to_json
      end

      before do
        stub_request(:post, "#{immich_url}/api/search/metadata")
          .to_return(status: 200, body: immich_response, headers: {})
        stub_request(:get, "#{immich_url}/api/assets/asset-id/thumbnail?size=preview")
          .to_return(status: 403, body: { message: 'Missing required permission: asset.view' }.to_json)
      end

      it 'reports missing asset.view permission' do
        patch '/settings', params: {
          settings: {
            'immich_url' => immich_url,
            'immich_api_key' => immich_api_key
          }
        }

        expect(response).to redirect_to(settings_path)
        follow_redirect!
        expect(flash[:alert]).to include('asset.view')
      end
    end

    context 'when photoprism settings change' do
      let(:photoprism_url) { 'https://photoprism.test' }
      let(:photoprism_api_key) { 'photoprism-key' }

      before do
        stub_request(:get, "#{photoprism_url}/api/v1/photos")
          .with(query: hash_including({ 'count' => '1', 'public' => 'true' }))
          .to_return(status: 200, body: [].to_json)
      end

      it 'verifies photoprism connection' do
        patch '/settings', params: {
          settings: {
            'photoprism_url' => photoprism_url,
            'photoprism_api_key' => photoprism_api_key
          }
        }

        expect(response).to redirect_to(settings_path)
        follow_redirect!
        expect(flash[:notice]).to include('Photoprism connection verified')
      end
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'redirects to the root path' do
        patch '/settings', params: params

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end

  describe 'GET /settings/users' do
    let!(:user) { create(:user, admin: true) }

    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

      sign_in user
    end

    context 'when self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'returns http success' do
        get '/settings/users'

        expect(response).to have_http_status(:success)
      end
    end

    context 'when not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'redirects to root path' do
        get '/settings/users'

        expect(response).to redirect_to(root_path)
      end
    end
  end
end

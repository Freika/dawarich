# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Integrations', type: :request do
  describe 'PATCH /settings/integrations' do
    let(:user) { create(:user) }
    let(:params) { { settings: { 'meters_between_routes' => '1000', 'minutes_between_routes' => '10' } } }

    before do
      sign_in user
    end

    it 'updates the user settings' do
      patch '/settings/integrations', params: params

      user.reload
      expect(user.settings['meters_between_routes']).to eq('1000')
      expect(user.settings['minutes_between_routes']).to eq('10')
    end

    it 'refreshes cached photos when requested' do
      Rails.cache.write("photos_#{user.id}_test", ['cached'])
      Rails.cache.write("photo_thumbnail_#{user.id}_immich_test", 'thumb')

      patch '/settings/integrations', params: params.merge(refresh_photos_cache: '1')

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
        patch '/settings/integrations', params: {
          settings: {
            'immich_url' => immich_url,
            'immich_api_key' => immich_api_key
          }
        }

        expect(response).to redirect_to(settings_integrations_path)
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
        patch '/settings/integrations', params: {
          settings: {
            'photoprism_url' => photoprism_url,
            'photoprism_api_key' => photoprism_api_key
          }
        }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:notice]).to include('Photoprism connection verified')
      end
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'redirects to the root path' do
        patch '/settings/integrations', params: params

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end
end

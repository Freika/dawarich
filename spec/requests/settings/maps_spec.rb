# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/maps', type: :request do
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
        expect(user.settings['maps']['name']).to eq('Test')
        expect(user.settings['maps']['url']).to eq('https://test.com')
      end

      it 'merges without clobbering v2 settings managed by the map panel' do
        user.settings['maps'] = {
          'distance_unit' => 'mi',
          'hidden_tile_categories' => ['roads'],
          'disabled_poi_groups' => ['shopping']
        }
        user.save!

        patch settings_maps_path,
              params: { maps: { name: 'Test', url: 'https://test.com', preferred_version: 'v1' } }

        maps = user.reload.settings['maps']
        expect(maps['name']).to eq('Test')
        expect(maps['preferred_version']).to eq('v1')
        expect(maps['distance_unit']).to eq('mi')
        expect(maps['hidden_tile_categories']).to eq(['roads'])
        expect(maps['disabled_poi_groups']).to eq(['shopping'])
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

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User feature toggles', type: :request do
  let(:user) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in user
  end

  describe 'PATCH /settings/general' do
    it 'turns features off' do
      patch settings_general_path, params: { family_enabled: '0', achievements_enabled: '0' }

      expect(user.reload.settings).to include('family_enabled' => false, 'achievements_enabled' => false)
    end

    it 'recomputes achievements silently when they are turned back on' do
      user.update!(settings: { 'achievements_enabled' => false })

      expect { patch settings_general_path, params: { achievements_enabled: '1' } }
        .to have_enqueued_job(Achievements::CheckJob).with(user.id, notify: false)
      expect(user.reload.settings['achievements_enabled']).to be true
    end

    it 'does not recompute achievements when they stay on' do
      expect { patch settings_general_path, params: { achievements_enabled: '1' } }
        .not_to have_enqueued_job(Achievements::CheckJob)
    end
  end

  describe 'GET /settings/general' do
    it 'renders both feature toggles' do
      get settings_general_index_path

      expect(response.body).to include('name="family_enabled"', 'name="achievements_enabled"')
    end
  end

  context 'when achievements are turned off' do
    before { user.update!(settings: { 'achievements_enabled' => false }) }

    it 'hides the navbar link and the unlock host' do
      get trips_path

      expect(response.body).not_to include(%(href="#{achievements_path}"))
      expect(response.body).not_to include('id="achievement-unlocks"')
    end

    it 'sends the collection page back to settings' do
      get achievements_path

      expect(response).to redirect_to(settings_general_index_path(anchor: 'features'))
    end

    it 'answers unlock polling with not found' do
      post next_achievement_unlock_path

      expect(response).to have_http_status(:not_found)
    end

    it 'treats public share links as not found' do
      create(:achievement_progress, user: user, achievement_key: 'exploration',
                                    state: { 'earned' => { 'DE-BY' => '2026-07-01T10:00:00Z' } })
      progress = create(:achievement_progress, user: user, achievement_key: 'country_de',
                                               sharing_enabled: true, sharing_uuid: SecureRandom.uuid)

      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to redirect_to(root_path)
    end
  end

  context 'when achievements are on' do
    it 'shows the navbar link' do
      get trips_path

      expect(response.body).to include(%(href="#{achievements_path}"))
    end
  end

  context 'when family is turned off for a family member' do
    before do
      family = create(:family, creator: user)
      create(:family_membership, user: user, family: family, role: :owner)
      user.update!(settings: { 'family_enabled' => false })
    end

    it 'hides the navbar link' do
      get trips_path

      expect(response.body).not_to include(%(href="#{family_path}"))
    end

    it 'sends the family page back to settings instead of the upgrade panel' do
      get family_path

      expect(response).to redirect_to(settings_general_index_path(anchor: 'features'))
    end

    it 'answers the API with a feature_disabled error' do
      get api_v1_families_mine_path, headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('feature_disabled')
    end
  end
end

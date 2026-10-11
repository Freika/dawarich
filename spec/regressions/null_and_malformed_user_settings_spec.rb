# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NULL and malformed user settings', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def store_settings(value)
    user.update_column(:settings, value)
    user.reload
  end

  it 'keeps partial user projections loadable without selecting settings' do
    expect(User.select(:id).find(user.id).id).to eq(user.id)
  end

  it 'uses safe unconfigured and family defaults when the stored container is NULL' do
    store_settings(nil)

    expect(user.immich_integration_configured?).to be(false)
    expect(user.photoprism_integration_configured?).to be(false)
    expect(user.family_sharing_enabled?).to be(false)
    expect(Families::LapseNotice.notified?(user)).to be(false)
  end

  it 'persists only supplied API settings after a NULL container' do
    store_settings(nil)

    result = Users::SettingsUpdater.new(user, { 'live_map_enabled' => false }).call

    expect(result.success?).to be(true)
    expect(user.reload.settings).to eq('live_map_enabled' => false)
  end

  it 'keeps a partial general settings write working after a NULL container' do
    store_settings(nil)

    patch settings_general_path(user), params: { timezone: 'Europe/Berlin' }

    expect(response).to have_http_status(:redirect)
    expect(user.reload.settings['timezone']).to eq('Europe/Berlin')
    expect(user.settings).not_to have_key('preferred_map_layer')
  end

  it 'renders Places without replacing a malformed non-object settings container' do
    store_settings(['opaque'])

    get places_path

    expect(response).to have_http_status(:ok)
    expect(user.reload.settings).to eq(['opaque'])
  end

  it 'refuses malformed API settings writes without changing stored data' do
    store_settings(['opaque'])

    result = Users::SettingsUpdater.new(user, { 'live_map_enabled' => false }).call

    expect(result.success?).to be(false)
    expect(user.reload.settings).to eq(['opaque'])
  end

  it 'refuses malformed integration settings before requesting a provider' do
    store_settings(['opaque'])

    result = Settings::Update.new(user, {}).call

    expect(result[:success]).to be(false)
    expect(user.reload.settings).to eq(['opaque'])
  end
end

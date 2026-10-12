# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Visits update persists only the modified keys', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

  before { sign_in user }

  it 'does not balloon users.settings with the full DEFAULT_VALUES hash' do
    patch settings_visits_path, params: { settings: { visit_radius_meters: 75 } }

    persisted_keys = user.reload.settings.keys.sort
    expect(persisted_keys).to contain_exactly('timezone', 'visit_radius_meters')
    expect(user.settings['visit_radius_meters']).to eq(75)
    expect(user.settings['timezone']).to eq('Europe/Berlin')
  end
end

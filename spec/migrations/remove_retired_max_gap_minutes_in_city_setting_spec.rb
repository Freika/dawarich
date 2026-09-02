# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901120000_remove_retired_max_gap_minutes_in_city_setting.rb')

RSpec.describe RemoveRetiredMaxGapMinutesInCitySetting do
  subject(:migration) { described_class.new }

  it 'drops the retired key while leaving the rest of the settings intact' do
    user = create(:user)
    user.update!(settings: user.settings.merge('max_gap_minutes_in_city' => 30, 'route_opacity' => 0.5))

    migration.up

    settings = user.reload.settings
    expect(settings).not_to have_key('max_gap_minutes_in_city')
    expect(settings['route_opacity']).to eq(0.5)
  end

  it 'leaves users that never stored the key untouched' do
    user = create(:user)
    user.update!(settings: user.settings.except('max_gap_minutes_in_city'))
    before = user.reload.settings

    migration.up

    expect(user.reload.settings).to eq(before)
  end

  it 'can run twice' do
    user = create(:user)
    user.update!(settings: user.settings.merge('max_gap_minutes_in_city' => 30))

    migration.up
    expect { migration.up }.not_to raise_error
    expect(user.reload.settings).not_to have_key('max_gap_minutes_in_city')
  end
end

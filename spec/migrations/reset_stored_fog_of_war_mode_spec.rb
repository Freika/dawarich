# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102120000_reset_stored_fog_of_war_mode.rb')

RSpec.describe ResetStoredFogOfWarMode do
  subject(:migration) { described_class.new }

  it 'drops the stored fog mode so every user gets the hexagon default' do
    user = create(:user)
    user.update!(settings: user.settings.merge('fog_of_war_mode' => 'points', 'fog_of_war_meters' => 80))

    migration.up

    settings = user.reload.settings
    expect(settings).not_to have_key('fog_of_war_mode')
    expect(settings['fog_of_war_meters']).to eq(80)
    expect(user.safe_settings.fog_of_war_mode).to eq('hexagons')
  end

  it 'can run twice' do
    user = create(:user)
    user.update!(settings: user.settings.merge('fog_of_war_mode' => 'points'))

    migration.up
    expect { migration.up }.not_to raise_error
    expect(user.reload.settings).not_to have_key('fog_of_war_mode')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievement stylesheets load only where achievements can appear', type: :request do
  let(:user) { create(:user) }
  let(:stylesheet_link) { /href="[^"]*achievements_spectral[^"]*\.css"/ }

  it 'leaves them out of the global stylesheet bundle' do
    expect(Rails.application.assets['application.css'].to_s).not_to include('.ach-card')
  end

  it 'links them on any page for a signed-in user, where the unlock deck can appear' do
    sign_in user

    get stats_path

    expect(response.body).to match(stylesheet_link)
  end

  it 'links them on the public badge page' do
    create(:achievement_progress, user:, achievement_key: 'exploration', state: {})
    shared = create(:achievement_progress, user:, achievement_key: 'country_de',
                                           sharing_enabled: true, sharing_uuid: SecureRandom.uuid)

    get shared_achievement_path(shared.sharing_uuid)

    expect(response.body).to match(stylesheet_link)
  end
end

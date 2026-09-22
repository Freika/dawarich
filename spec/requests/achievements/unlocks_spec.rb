# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievement unlock reveals' do
  let(:user) { create(:user) }

  before do
    Flipper.enable(:achievements)
    sign_in user
  end

  after { Flipper.disable(:achievements) }

  it 'renders a collectible deck, acknowledges each card once, and leaves no popup after the last card' do
    create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA',
                     geom: 'MULTIPOLYGON (((2 48, 2 49, 3 49, 3 48, 2 48)))')
    create(:achievement_progress, user: user, achievement_key: 'exploration',
                                  state: { 'earned' => { 'FR' => Time.current.iso8601 } })
    first = Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
    Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'DE')

    post next_achievement_unlock_path, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload['id']).to eq(first.id)
    expect(payload['remaining']).to eq(2)
    expect(payload['html']).to include('France', 'ach-unlock-back', 'ach-spectral')
    expect(first.reload.seen_at).to be_nil

    post seen_achievement_unlock_path(first), params: { claim_token: payload['token'] }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(first.reload.seen_at).to be_present

    post next_achievement_unlock_path, params: { batch_end_id: payload['batch_end_id'] }, as: :json
    expect(response.parsed_body['remaining']).to eq(1)
  end

  it 'never lets one account acknowledge another account’s card' do
    other = create(:user)
    event = Achievements::UnlockEvent.create!(user: other, kind: 'geography', key: 'FR', claim_token: 'secret')

    post seen_achievement_unlock_path(event), params: { claim_token: 'secret' }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(event.reload.seen_at).to be_nil
  end

  it 'includes the reveal host on signed-in application pages' do
    get achievements_path

    expect(response.body).to include('data-controller="achievement-unlocks"')
  end

  it 'includes the reveal host on the full-screen map layout too' do
    get map_v2_path

    expect(response.body).to include('data-controller="achievement-unlocks"')
  end

  it 'does not expose the reveal endpoint when the feature is disabled' do
    Flipper.disable(:achievements)

    post next_achievement_unlock_path, as: :json

    expect(response).to have_http_status(:not_found)
  end
end

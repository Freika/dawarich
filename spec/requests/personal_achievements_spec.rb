# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Personal achievement collections' do
  let(:user) { create(:user) }
  let(:place) { create(:place, user: user, name: 'My lake', latitude: 52.52, longitude: 13.405) }

  before { sign_in user }

  it 'lets the owner select a place, view both cards and remove it again' do
    post achievement_selections_path, params: { place_id: place.id }
    expect(response).to redirect_to(achievement_cards_path)
    Achievements::CollectionChecker.new(user, notify: false).call

    get achievement_cards_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css('[data-testid="personal-achievement-cards"] .card-title').size).to eq(8)
    card = user.achievement_collectibles.find_by!(series: 'seasons')
    get achievement_card_path(card)
    expect(response.body).to include('My lake', 'Place timezone: Europe/Berlin', '0/4 seasons')

    delete achievement_selection_path(user.achievement_selections.first)
    Achievements::CollectionChecker.new(user, notify: false).call
    get achievement_card_path(card)
    expect(response).to have_http_status(:not_found)
  end

  it 'never selects another users place or exposes their private cards' do
    other = create(:user)
    other_place = create(:place, user: other)
    post achievement_selections_path, params: { place_id: other_place.id }
    expect(response).to have_http_status(:not_found)
    expect(user.achievement_selections).to be_empty
  end

  it 'allows explicit sharing but immediately hides it when a privacy zone is added' do
    selection = Achievements::Selection.create!(user: user, place: place)
    Achievements::CollectionChecker.new(user, notify: false).call
    card = user.achievement_collectibles.find_by!(series: 'seasons')
    patch toggle_sharing_achievement_card_path(card), params: { enabled: true }, as: :json
    expect(response).to have_http_status(:ok)
    uuid = response.parsed_body.fetch('uuid')
    sign_out user
    get shared_collectible_path(uuid), params: { embed: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('My lake')

    tag = create(:tag, user: user, privacy_radius_meters: 500)
    place.tags << tag
    get shared_collectible_path(uuid)
    expect(response).to have_http_status(:not_found)
    get shared_collectible_image_path(uuid)
    expect(response).to have_http_status(:not_found)
    expect(selection).to be_persisted
  end

  it 'accepts only valid IANA place timezone overrides' do
    selection = Achievements::Selection.create!(user: user, place: place)
    patch achievement_selection_path(selection), params: { timezone: 'Pacific/Auckland' }
    expect(selection.reload.timezone).to eq('Pacific/Auckland')
    patch achievement_selection_path(selection), params: { timezone: 'invented' }
    expect(selection.reload.timezone).to eq('Pacific/Auckland')
  end
end

RSpec.describe 'Geographic collection sharing' do
  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: 'shared-geo', completed_at: Time.current) }

  before do
    sign_in user
    allow(Exploration::Geography).to receive_messages(current: dataset, install!: dataset)
    rows = [[52.52, 13.405, Time.utc(2025, 1, 1, 10)],
            [-33.86, 151.2, Time.utc(2025, 1, 2, 10)]].flat_map do |lat, lon, at|
      (0..10).map do |minute|
        { user_id: user.id, timestamp: at.to_i + minute * 60, lonlat: "POINT(#{lon} #{lat})",
          created_at: Time.current, updated_at: Time.current }
      end
    end
    Point.insert_all!(rows)
    Achievements::CollectionChecker.new(user, notify: false).call
  end

  it 'serves anonymous masked cards and uncached OG images, hiding dirty evidence immediately' do
    card = user.achievement_collectibles.find_by!(series: 'milestone', subject_key: 'north_south')
    expect(card.level).to eq(1)
    patch toggle_sharing_achievement_card_path(card), params: { enabled: true }, as: :json
    expect(response).to have_http_status(:ok)
    uuid = response.parsed_body.fetch('uuid')
    sign_out user
    get shared_collectible_path(uuid), params: { embed: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2/2 regions')
    expect(response.headers['Cache-Control']).to include('no-store')
    get shared_collectible_image_path(uuid)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.body.bytes.first(8)).to eq([137, 80, 78, 71, 13, 10, 26, 10])

    place = create(:place, user: user, latitude: 52.52, longitude: 13.405)
    place.tags << create(:tag, user: user, privacy_radius_meters: 1000)
    get shared_collectible_path(uuid)
    expect(response).to have_http_status(:not_found)
    get shared_collectible_image_path(uuid)
    expect(response).to have_http_status(:not_found)
    Achievements::CollectionChecker.new(user, notify: false).call
    get shared_collectible_path(uuid)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('1/2 regions')
    drawing = Nokogiri::HTML(response.body)
    expect(drawing.css('[data-color]').map { |node| node['data-color'] }).to eq([Achievements::GlobeArtwork::REGION_COLORS.fetch('south')])
    expect(drawing.css('[data-detail]').size).to eq(4)
    expect(response.body).not_to include('Unlocked ·')
    expect(card.reload.level).to eq(1)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Saved place map visibility', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Turbo-Frame' => 'place-drawer' } }
  let(:private_coordinates) { { latitude: 52.52, longitude: 13.405 } }
  let(:public_coordinates) { { latitude: 48.85, longitude: 2.35 } }
  let(:tag) { create(:tag, user:, name: 'New tag', icon: '🌿') }

  before do
    sign_in user
    anchor = create(:place, user:, **private_coordinates)
    anchor.tags << create(:tag, :privacy_zone, user:)
    foreign_anchor = create(:place, **public_coordinates)
    foreign_anchor.tags << create(:tag, :privacy_zone, user: foreign_anchor.user)
  end

  def relay
    Nokogiri::HTML(response.body).at_css('#place-creation-data')
  end

  def expect_hidden(place)
    expect(response).to have_http_status(:ok)
    expect(relay['data-removed-id']).to eq(place.id.to_s)
    expect(relay['data-place']).to be_nil
    expect(relay.to_html).not_to match(/latitude|longitude|coordinates/)
  end

  def expect_visible(place)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(relay['data-place'])).to include(
      'id' => place.id, 'name' => place.name, 'latitude' => place.lat, 'longitude' => place.lon,
      'geofence' => true, 'tags' => [include('id' => tag.id, 'name' => tag.name, 'icon' => tag.icon)]
    )
  end

  it 'creates a removal relay inside an owner zone and a full relay outside it with a new tag' do
    visit = create(:visit, user:)
    post places_path, params: { visit_id: visit.id, place: { name: 'Private cafe', **private_coordinates } },
                      as: :turbo_stream
    expect_hidden(user.places.find_by!(name: 'Private cafe'))
    expect(relay['data-visit-id']).to eq(visit.id.to_s)

    post places_path, params: { place: { name: 'Public cafe', **public_coordinates,
                                        geofence: true, tag_ids: [tag.id] } }, as: :turbo_stream
    expect_visible(user.places.find_by!(name: 'Public cafe'))
  end

  it 'updates a removal relay when moved inside a zone and a full relay when moved outside it' do
    place = create(:place, user:, **public_coordinates)
    patch place_path(place), params: { place: private_coordinates }, headers:, as: :turbo_stream
    expect_hidden(place.reload)
    expect(relay['data-updated']).to eq('true')

    patch place_path(place), params: { place: { **public_coordinates, geofence: true, tag_ids: [tag.id] } },
                             headers:, as: :turbo_stream
    expect_visible(place.reload)
  end

  it 'merges a hidden survivor without coordinates while removing its duplicate and relays a visible survivor' do
    survivor = create(:place, user:, **private_coordinates)
    duplicate = create(:place, user:, **public_coordinates)
    post merge_place_path(survivor), params: { duplicate_place_id: duplicate.id }, headers:, as: :turbo_stream
    expect_hidden(survivor)
    expect(relay['data-duplicate-id']).to eq(duplicate.id.to_s)

    survivor = create(:place, user:, geofence: true, **public_coordinates)
    duplicate = create(:place, user:, **public_coordinates)
    duplicate.tags << tag
    post merge_place_path(survivor), params: { duplicate_place_id: duplicate.id }, headers:, as: :turbo_stream
    expect_visible(survivor.reload)
    expect(relay['data-removed-id']).to eq(duplicate.id.to_s)
  end
end

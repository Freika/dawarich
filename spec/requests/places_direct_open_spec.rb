# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place direct opening', type: :request do
  let(:user) { create(:user) }
  let(:place) { create(:place, user:, name: 'Map place') }

  before { sign_in user }

  it 'redirects a direct place request to the map with the place open' do
    get place_path(place)

    expect(response).to redirect_to(map_v2_path(place_id: place.id))
  end

  it 'keeps the place drawer available to its Turbo frame' do
    get place_path(place), headers: { 'Turbo-Frame' => 'place-drawer' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="place-drawer"', 'Map place')
  end

  it 'saves a note from an HTML request without raising a server error' do
    patch place_path(place), params: { place: { note: 'A saved note' } }

    expect(response).to redirect_to(map_v2_path(place_id: place.id))
    expect(place.reload.note).to eq('A saved note')
  end

  it 'redirects an invalid HTML update without raising a server error' do
    patch place_path(place), params: { place: { name: '' } }

    expect(response).to redirect_to(map_v2_path(place_id: place.id))
    expect(place.reload.name).to eq('Map place')
  end

  it 'loads the map with a place drawer and its location for a place deep link' do
    get map_v2_path(place_id: place.id)

    document = Nokogiri::HTML(response.body)
    map = document.at_css('#maps-maplibre-container')
    expect(response).to have_http_status(:ok)
    expect(map['data-maps--maplibre-place-latitude-value']).to eq(place.lat.to_s)
    expect(map['data-maps--maplibre-place-longitude-value']).to eq(place.lon.to_s)
    expect(map.at_css('turbo-frame#place-drawer')['src']).to eq(place_path(place))
  end

  it 'does not disclose another user place through the map deep link' do
    other_place = create(:place, user: create(:user))

    get map_v2_path(place_id: other_place.id)

    expect(response).to have_http_status(:not_found)
  end
end

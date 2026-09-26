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

  it "labels the drawer's Close and Edit buttons in the reader's language" do
    { 'en' => %w[Close Edit], 'de' => %w[Schließen Bearbeiten] }.each do |locale, (close, edit)|
      get place_path(place, locale:), headers: { 'Turbo-Frame' => 'place-drawer' }

      drawer = Nokogiri::HTML(response.body)
      expect(drawer.at_css('button[data-action="place-detail#close"]')['aria-label']).to eq(close)
      expect(drawer.at_css('button[data-entity-type="place"]').text.strip).to eq(edit)
    end
  end

  it "opens the map's place editor from the drawer's Edit button" do
    get place_path(place), headers: { 'Turbo-Frame' => 'place-drawer' }

    edit = Nokogiri::HTML(response.body).at_css('button[data-entity-type="place"]')
    expect(edit['data-action']).to eq('maps--maplibre#handleEdit')
    expect(edit['data-id']).to eq(place.id.to_s)
    expect(edit['disabled']).to be_nil
  end

  it "refreshes the open drawer when the map's place editor saves the place" do
    patch place_path(place), params: { place: { name: 'Renamed on the map' } }, as: :turbo_stream

    expect_turbo_stream_action('update', 'place-drawer')
    expect(response.body).to include('Renamed on the map')
    expect_turbo_stream_action('replace', 'place-creation-data')
  end

  it "deletes the place from the drawer's Delete button and stays on the map" do
    get place_path(place), headers: { 'Turbo-Frame' => 'place-drawer' }
    delete_form = Nokogiri::HTML(response.body).at_css('form:has(button.place-drawer__action--delete)')
    expect(delete_form['action']).to eq(place_path(place))
    expect(delete_form.at_css('input[name="_method"]')['value']).to eq('delete')
    expect(delete_form['data-action']).to eq('turbo:submit-end->place-detail#deleted')
    expect(delete_form['data-place-detail-id-param']).to eq(place.id.to_s)

    delete delete_form['action'], headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream

    expect(Place.exists?(place.id)).to be(false)
    expect_turbo_stream_response
    expect_flash_stream('Place was successfully destroyed.')
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

  it 'keeps the map place creation form blank on a place deep link' do
    place.update!(note: 'Private note')

    get map_v2_path(place_id: place.id)

    creation_form = Nokogiri::HTML(response.body).at_css('form[action="/places"]')
    expect(creation_form.at_css('input[name="place[name]"]')['value']).to be_nil
    expect(creation_form.at_css('textarea[name="place[note]"]').text.strip).to be_empty
  end

  it 'does not disclose another user place through the map deep link' do
    other_place = create(:place, user: create(:user))

    get map_v2_path(place_id: other_place.id)

    expect(response).to have_http_status(:not_found)
  end
end

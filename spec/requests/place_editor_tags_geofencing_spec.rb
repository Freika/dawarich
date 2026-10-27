# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place editor tags and geofencing', type: :request do
  let(:user) { create(:user, settings: { timezone: 'Europe/Berlin' }) }
  let(:place) { create(:place, user:, name: 'Garden', geofence: true) }

  before { sign_in user }

  def document
    Nokogiri::HTML(response.body)
  end

  def saved_place_data
    JSON.parse(document.at_css('#place-creation-data')['data-place'])
  end

  %w[editor creation].each do |surface|
    it "creates and checks a new tag inline in the #{surface} without saving the place" do
      post tags_path, params: { inline: surface, tag: { name: 'Garden walks', icon: '🌿' } }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      tag = user.tags.find_by!(name: 'Garden walks')
      expect(tag).to have_attributes(icon: '🌿', color: '#6ab0a4')
      stream = document.at_css("turbo-stream[target='#{surface}-place-tags']")
      checkbox = Nokogiri::HTML.fragment(stream.at_css('template').inner_html).at_css('input[type=checkbox]')
      expect(checkbox['value']).to eq(tag.id.to_s)
      expect(checkbox['checked']).to be_present
      expect(checkbox['name']).to eq('place[tag_ids][]')
      expect(response.body).not_to include('target="place-drawer"')
      expect(tag.places).to be_empty
    end
  end

  it 'returns inline validation errors without replacing selected tags or editor fields' do
    post tags_path, params: { inline: 'editor', tag: { name: '', icon: 'abc' } }, as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.css('turbo-stream').map { |stream| stream['target'] }).to eq(['editor-tag-errors'])
    expect(response.body).to include('Name', 'Icon')
    expect(user.tags.reload).to be_empty
  end

  it 'rejects a duplicate inline tag while allowing the same name for another user' do
    create(:tag, user:, name: 'Garden walks')
    create(:tag, name: 'Elsewhere')

    expect do
      post tags_path, params: { inline: 'creation', tag: { name: 'Garden walks' } }, as: :turbo_stream
    end.not_to change(Tag, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('already been taken')

    post tags_path, params: { inline: 'creation', tag: { name: 'Elsewhere' } }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(user.tags.find_by(name: 'Elsewhere')).to be_present
  end

  it 'restricts inline tag creation to the signed-in user and the default colour' do
    stranger = create(:user)
    post tags_path, params: {
      inline: 'editor', tag: { name: 'Mine', icon: '🌿', user_id: stranger.id,
                              privacy_radius_meters: 1000, color: '#ffffff' }
    }, as: :turbo_stream

    expect(user.tags.find_by!(name: 'Mine')).to have_attributes(color: '#6ab0a4', privacy_radius_meters: nil)
    expect(stranger.tags).to be_empty
  end

  it 'requires authentication for inline tag creation' do
    sign_out user
    expect do
      post tags_path, params: { inline: 'editor', tag: { name: 'Mine' } }, as: :turbo_stream
    end.not_to change(Tag, :count)
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'shares accessible inline tag controls between the page editor and creation modal without nested forms' do
    get place_path(place)
    expect(document.css('form form')).to be_empty
    expect(document.at_css('[data-controller~="inline-tag"]')).to be_present
    expect(document.at_css('[name="tag[name]"]')['form']).to eq('editor-inline-tag-form')
    expect(document.at_css('[name="tag[icon]"]')['form']).to eq('editor-inline-tag-form')

    get map_v2_path
    expect(document.at_css('[data-controller~="place-creation"]').css('form form')).to be_empty
    expect(document.at_css('[name="tag[name]"]')['form']).to eq('creation-inline-tag-form')
    expect(document.at_css('[name="place[geofence]"][type=checkbox]')['checked']).to be_nil
  end

  it 'shows each privacy tag with its own privacy radius rather than the Visit Radius' do
    place.update!(visit_radius: 75)
    place.tags << create(:tag, user:, name: 'Home', privacy_radius_meters: 500)
    place.tags << create(:tag, user:, name: 'Quiet', privacy_radius_meters: 1200)
    place.tags << create(:tag, user:, name: 'Public')

    get place_path(place)

    expect(document.css('[data-testid="place-privacy-line"]').map(&:text)).to contain_exactly(
      'Hidden by tag Home, 500 m', 'Hidden by tag Quiet, 1200 m'
    )
  end

  it 'labels the geofence boundary in place info only while geofencing is enabled' do
    get place_path(place)
    expect(document.at_css('[data-testid="place-geofence-legend"]').text.strip).to eq('Geofence boundary')

    place.update!(geofence: false)
    get place_path(place)
    expect(document.at_css('[data-testid="place-geofence-legend"]')).to be_nil
  end

  it 'creates a geofence with selected inline tags and includes its state in the map update' do
    tag = create(:tag, user:, name: 'Garden walks')
    post places_path, params: { place: { name: 'Garden', latitude: 52.5, longitude: 13.4,
                                        geofence: '1', tag_ids: [tag.id] } }, as: :turbo_stream

    expect(user.places.last).to be_geofence
    expect(user.places.last.tags).to contain_exactly(tag)
    expect(saved_place_data['geofence']).to be(true)
  end

  it 'defaults new places to geofencing off and relays changes from the editor' do
    post places_path, params: { place: { name: 'Cafe', latitude: 52.5, longitude: 13.4 } }, as: :turbo_stream
    created = user.places.last
    expect(created).not_to be_geofence
    expect(saved_place_data['geofence']).to be(false)

    patch place_path(created), params: { place: { geofence: '1' } },
                               headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream
    expect(saved_place_data['geofence']).to be(true)
  end

  it 'shows only the latest ten real events for this user and place in local time with a filtered log link' do
    oldest = Time.utc(2026, 10, 1, 10)
    11.times do |index|
      create(:geofence_event, user:, place:, occurred_at: oldest + index.hours,
                             event_type: index.even? ? :enter : :leave, source: :server_inferred)
    end
    create(:geofence_event, user:, place:, synthetic: true, occurred_at: oldest + 12.hours)
    create(:geofence_event, place:, occurred_at: oldest + 13.hours)
    create(:geofence_event, user:, occurred_at: oldest + 14.hours)

    get place_path(place)

    events = document.css('[data-testid="place-geofence-event"]')
    expect(events.size).to eq(10)
    expect(events.first.text).to include('Entered', 'Location points', '22:00')
    expect(Time.iso8601(events.last.at_css('time')['datetime'])).to eq(oldest + 1.hour)
    expect(document.at_css('[data-testid="place-geofence-events-link"]')['href'])
      .to eq(settings_geofencing_path(place_id: place.id))
  end

  it 'shows an empty event history for a geofence with no events and a disabled message otherwise' do
    get place_path(place)
    expect(response.body).to include('No enter or leave events yet.')

    create(:geofence_event, user:, place:)
    place.update!(geofence: false)
    get place_path(place)
    expect(document.css('[data-testid="place-geofence-event"]')).to be_empty
    expect(response.body).to include('Turn on enter and leave notifications to record events for this place.')
  end

  it 'does not expose another user place or its event history' do
    other = create(:place, :geofence)
    create(:geofence_event, place: other, user: other.user)
    get place_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it 'serializes geofences for the places layer while keeping privacy-zone places masked' do
    public_place = create(:place, user:, name: 'Visible', latitude: 48.8, longitude: 2.3)
    place.tags << create(:tag, user:, privacy_radius_meters: 500)
    headers = { 'Authorization' => "Bearer #{user.api_key}" }

    get '/api/v1/places', params: { mask_privacy_zones: true, filter: 'all' }, headers: headers
    expect(response.parsed_body.map { |item| item['id'] }).to contain_exactly(public_place.id)
    expect(response.parsed_body.first['geofence']).to be(false)

    get '/api/v1/places', params: { filter: 'all' }, headers: headers
    expect(response.parsed_body.find { |item| item['id'] == place.id }['geofence']).to be(true)
  end
end

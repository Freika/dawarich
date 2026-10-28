# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Archived Place UI', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it 'offers reversible archive controls and a badge in both editor surfaces' do
    place = create(:place, user:, geofence: true)
    visit = create(:visit, user:, place:, status: :confirmed)
    tag = create(:tag, user:, privacy_radius_meters: 100)
    place.tags << tag

    get place_url(place, map_panel: '1')
    doc = Nokogiri::HTML(response.body)
    form = doc.at_css('form[data-testid="place-archive-form"]')
    expect(form).to be_present
    expect(form.at_css('input[name="_method"]')['value']).to eq('patch')
    expect(form.at_css('input[name="place[archived]"]')['value']).to eq('1')
    expect(form.at_css('input[name="map_panel"]')['value']).to eq('1')
    expect(form.at_css('button').text).to include('Archive')
    expect(doc.at_css('[data-testid="place-archive-hint"]').text)
      .to include('visits', 'new visits', 'geofenc', 'privacy')
    expect(doc.at_css('[data-testid="place-archived-badge"]')).to be_nil

    patch place_url(place), params: { place: { archived: '1' }, map_panel: '1' },
                            headers: { 'Turbo-Frame' => 'place-drawer' }, as: :turbo_stream
    expect(response).to be_successful
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[data-testid="place-archived-badge"]').text).to eq('Archived')
    expect(doc.at_css('form[data-testid="place-archive-form"] input[name="place[archived]"]')['value']).to eq('0')
    expect(doc.at_css('form[data-testid="place-archive-form"] button').text).to include('Unarchive')
    expect(visit.reload.place).to eq(place)
    expect(place.reload).to have_attributes(geofence: true, tags: [tag])

    get place_url(place)
    expect(Nokogiri::HTML(response.body).at_css('[data-testid="place-archived-badge"]')).to be_present
    patch place_url(place), params: { place: { archived: '0' } }
    expect(place.reload).not_to be_archived
  end

  it 'renders an Archived status, row badge and independent bulk archive forms' do
    place = create(:place, user:, archived: true)
    get places_url(filter: 'archived')
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('select[name="filter"] option[value="archived"][selected]').text).to eq('Archived')
    expect(doc.at_css("tr[data-place-id='#{place.id}'] [data-testid='place-archived-badge']").text).to eq('Archived')
    %w[archive unarchive].each do |operation|
      button = doc.at_css("button[name='operation'][value='#{operation}']")
      expect(button).to be_present
      expect(button.ancestors('form').first.at_css('select[name="tag_id"]')).to be_nil
    end
  end

  it 'bulk archives and unarchives only selected owned places while keeping visits and tags' do
    place = create(:place, user:, geofence: true)
    untouched = create(:place, user:)
    foreign = create(:place)
    visit = create(:visit, user:, place:, status: :confirmed)
    tag = create(:tag, user:)
    place.tags << tag
    event = create(:geofence_event, user:, place:)

    %w[archive unarchive].each do |operation|
      patch bulk_update_places_url(filter: 'archived', q: 'Home'),
            params: { place_ids: [place.id, foreign.id], operation: }, as: :turbo_stream
      expect(response).to redirect_to(places_url(filter: 'archived', q: 'Home'))
      expect(flash[:alert]).to be_nil
      expect(place.reload.archived?).to eq(operation == 'archive')
      expect(place).to have_attributes(geofence: true, tags: [tag])
      expect(visit.reload.place_id).to eq(place.id)
      expect(event.reload.place_id).to eq(place.id)
      expect(foreign.reload).not_to be_archived
      expect(untouched.reload).not_to be_archived
    end
  end

  it 'explains that deleted places keep named geofence events in every locale' do
    place = create(:place, user:)
    retained = {
      en: 'Geofence events are kept with the place name',
      de: 'Geofencing-Ereignisse bleiben mit dem Ortsnamen erhalten',
      es: 'Los eventos de geocerca se conservan con el nombre del lugar',
      fr: 'Les événements de géorepérage sont conservés avec le nom du lieu',
      pl: 'Zdarzenia geostrefy zostają zachowane z nazwą miejsca',
      ca: 'Els esdeveniments de geotanca es conserven amb el nom del lloc', zh: '地理围栏事件将保留，并附有地点名称'
    }
    retained.each do |locale, text|
      get place_url(place, locale:)
      confirmation = Nokogiri::HTML(response.body).at_css('.place-drawer__action--delete')['data-turbo-confirm']
      expect(confirmation).to include(text)
      get places_url(locale:)
      expect(response.body).to include(text)
    end
  end
end

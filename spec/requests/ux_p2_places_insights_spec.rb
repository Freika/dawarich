# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'P2 places and analytics journeys', type: :request do
  let(:user) { create(:user, admin: true) }
  before { sign_in user }

  it 'finds an owned place by partial name and tag without exposing another owner' do
    tag = create(:tag, user: user)
    match = create(:place, user: user, name: 'Café Süd')
    match.tags << tag
    create(:place, user: user, name: 'Unrelated')
    foreign = create(:place, name: 'Café elsewhere')
    get places_path, params: { q: 'Café', tag_ids: [tag.id] }
    names = Nokogiri::HTML(response.body).css('[data-testid="place-list-name"]').map(&:text)
    expect(names).to eq([match.name])
    expect(response.body).not_to include(foreign.name)
  end

  it 'offers creation from Places and persists the HTML form' do
    get places_path
    expect(Nokogiri::HTML(response.body).at_css('a[data-testid="new-place"]')).to be_present
    post places_path, params: { place: { name: 'New place', latitude: 52.52, longitude: 13.4, visit_radius: 75 } }
    expect(response).to redirect_to(place_path(user.places.last))
  end

  it 'edits a place and returns to the same filtered list' do
    place = create(:place, user: user)
    tag = create(:tag, user: user)
    get "/places/#{place.id}/edit", params: { q: 'Coffee', filter: 'unconfirmed', page: 2 }
    expect(response).to be_successful
    patch place_path(place), params: { q: 'Coffee', filter: 'unconfirmed', page: 2,
                                      place: { name: 'Coffee new', visit_radius: 100, tag_ids: [tag.id] } }
    expect(response).to redirect_to(place_path(place, q: 'Coffee', filter: 'unconfirmed', page: 2))
    get response.location
    back = Nokogiri::HTML(response.body).at_css('[data-testid="back-to-places"]')
    expect(back['href']).to eq(places_path(q: 'Coffee', filter: 'unconfirmed', page: 2))
    expect(place.reload.name).to eq('Coffee new')
    expect(place.visit_radius).to eq(100)
    expect(place.tags).to contain_exactly(tag)
  end

  it 'offers first-data actions instead of a stack of empty analytics' do
    get insights_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('[data-testid="insights-empty"]')).to be_present
    expect(page.css('turbo-frame#insights_details')).to be_empty
    expect(page.css('a').any? { |a| a['href'] == new_import_path }).to be(true)
  end

  it 'distinguishes unresolved country names from missing coordinates' do
    create(:point, user: user, timestamp: Time.utc(2026, 4, 5).to_i)
    create(:stat, user: user, year: 2026, month: 4, distance: 172_000, toponyms: [])
    get insights_path(year: 2026)
    expect(response.body).to include('Not yet identified')
    get '/stats/2026/4'
    expect(response.body).not_to include('No location data available for this month')
  end

  it 'gives icon-only theme and navigation controls accessible names' do
    get map_v2_path
    page = Nokogiri::HTML(response.body)
    theme = page.at_css('a[href*="/settings/theme"]')
    expect(theme['aria-label']).to be_present
    nav = page.at_css('.navbar')
    nav.css('summary').each do |summary|
      expect(summary.text.strip.presence || summary['aria-label']).to be_present
    end
  end
end

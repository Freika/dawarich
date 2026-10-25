# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit titles after renaming a tagged place', type: :request do
  it 'shows the saved place name instead of the old address while keeping its tag' do
    user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
    address = 'Imaginary Current Lane 42'
    place = create(:place, user: user, name: address, source: :photon,
                           latitude: -48.123456, longitude: -139.654321)
    tag = create(:tag, user: user, name: 'synthetic-home', icon: '🏠', color: '#4CAF50')
    place.tags << tag
    started_at = Time.utc(2026, 10, 20, 10)
    visit = create(:visit, user: user, area: nil, place: place, name: address,
                           started_at: started_at, ended_at: started_at + 1.hour,
                           duration: 60, status: :confirmed)

    patch "/api/v1/places/#{place.id}",
          params: { place: { name: 'Synthetic Ocean Home', tag_ids: [tag.id] } },
          headers: { 'Authorization' => "Bearer #{user.api_key}" }

    expect(response).to have_http_status(:ok)
    expect(place.reload.name).to eq('Synthetic Ocean Home')

    sign_in user
    get '/map/timeline_feeds', params: {
      start_at: started_at.beginning_of_day.to_i,
      end_at: started_at.end_of_day.to_i
    }

    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("#visit_entry_#{visit.id}")
    expect(row).to be_present
    expect(row.css('.visit-tag').text).to include('#synthetic-home')
    expect(row.at_css("[data-testid='visit-name-#{visit.id}']").text).to eq('Synthetic Ocean Home')
  end
end

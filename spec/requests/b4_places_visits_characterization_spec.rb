# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'B4 places and visits characterization', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /places' do
    it 'shows 20 places on the first page and the remaining place on page two' do
      places = create_list(:place, 21, user:)

      get places_path

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css('tbody tr').size).to eq(20)
      first_page_names = Nokogiri::HTML(response.body).css('tbody tr td:first-child').map(&:text)
      expect(first_page_names).to all(be_in(places.map(&:name)))

      get places_path, params: { page: 2 }

      expect(response).to have_http_status(:ok)
      second_page_names = Nokogiri::HTML(response.body).css('tbody tr td:first-child').map(&:text)
      expect(second_page_names.size).to eq(1)
      expect(second_page_names.first).to be_in(places.map(&:name))
      expect(first_page_names).not_to include(second_page_names.first)
    end
  end

  describe 'DELETE /places/:id' do
    it 'returns to the requested page, which shows the empty state once its last place is gone' do
      places = create_list(:place, 21, user:)
      get places_path, params: { page: 2 }
      last_name = Nokogiri::HTML(response.body).at_css('tbody tr td:first-child').text
      last_place = places.find { |place| place.name == last_name }

      delete place_path(last_place, page: 2)

      expect(response).to redirect_to(places_url(page: 2))
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      list = Nokogiri::HTML(response.body).at_css('#places')
      expect(list.css('h1').map { |heading| heading.text.strip }).to eq(['Hello there!'])
      expect(list.css('table')).to be_empty
      expect(user.places.count).to eq(20)
    end
  end

  describe 'GET /places/:id' do
    it 'shows only active visits in the drawer and active visit count' do
      place = create(:place, user:, name: 'B4 Cafe')
      create(:visit, place:, user:, name: 'Active visit', status: 'confirmed', area: nil)
      create(:visit, place:, user:, name: 'Deleted visit', status: 'confirmed', deleted_at: 1.day.ago, area: nil)

      get place_path(place), headers: { 'Turbo-Frame' => 'place-drawer' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Active visit')
      expect(response.body).not_to include('Deleted visit')
      expect(response.body).to include('1 visit')
    end
  end

  describe 'PATCH /settings/visits' do
    it 'saves all visit settings and preserves unrelated settings' do
      user.update!(settings: user.settings.merge('locale' => 'de', 'onboarding_completed' => true))

      patch settings_visits_path, params: {
        settings: { visit_radius_meters: '75', visit_min_points: '4', visit_min_duration_minutes: '7' }
      }

      expect(response).to redirect_to(settings_visits_path)
      user.reload
      expect(user.safe_settings.visit_radius_meters).to eq(75)
      expect(user.safe_settings.visit_min_points).to eq(4)
      expect(user.safe_settings.visit_min_duration_minutes).to eq(7)
      expect(user.settings).to include('locale' => 'de', 'onboarding_completed' => true)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manual area assignment for visits', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
  let(:area) { create(:area, user: user, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 200) }
  let(:visit) { create(:visit, user: user, name: 'before', place: nil, area: nil) }

  describe 'PATCH /api/v1/visits/:id' do
    let(:auth_headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'translates area_id to the mapped canonical Place' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id } },
            headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(visit.reload.area_id).to be_nil
      expect(visit.place).to eq(LegacyAreaPlaceMapping.find_by!(area:).place)
    end

    it 'updates the location label to the area name without replacing the custom name' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id } },
            headers: auth_headers

      expect(visit.reload).to have_attributes(name: 'before', location_label: 'Home')
    end

    it 'preserves a user-provided name even when area_id is set' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id, name: 'Custom label' } },
            headers: auth_headers

      expect(visit.reload.name).to eq('Custom label')
    end

    it 'rejects a foreign area with 422' do
      foreign_user = create(:user)
      foreign_area = create(:area, user: foreign_user, name: 'Foreign', latitude: 1.0, longitude: 1.0, radius: 100)

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: foreign_area.id } },
            headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload.area_id).to be_nil
    end

    it 'rejects conflicting place_id and area_id' do
      place = create(:place, user: user, name: 'Coffee Shop')

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { place_id: place.id, area_id: area.id } },
            headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload).to have_attributes(place_id: nil, area_id: nil)
    end

    it 'clears area_id when an empty value is sent' do
      visit.update!(area: area)
      expect(visit.reload.area_id).to eq(area.id)

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: '' } },
            headers: auth_headers

      expect(visit.reload.area_id).to be_nil
    end

    it 'rejects a non-numeric area_id with 422' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: 'banana' } },
            headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload.area_id).to be_nil
    end

    it 'rejects a foreign place with 422' do
      foreign_user = create(:user)
      foreign_place = create(:place, user: foreign_user, name: 'Stranger Place')

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { place_id: foreign_place.id } },
            headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload.place_id).to be_nil
    end
  end

  describe 'PATCH /visits/:id (web controller)' do
    before { sign_in user }

    it 'translates area_id to the mapped canonical Place' do
      patch "/visits/#{visit.id}",
            params: { visit: { area_id: area.id } }

      expect(visit.reload.area_id).to be_nil
      expect(visit.place).to eq(LegacyAreaPlaceMapping.find_by!(area:).place)
      expect(visit.reload).to have_attributes(name: 'before', location_label: 'Home')
    end

    it 'rejects a foreign area' do
      foreign_user = create(:user)
      foreign_area = create(:area, user: foreign_user, name: 'Foreign', latitude: 1.0, longitude: 1.0, radius: 100)

      patch "/visits/#{visit.id}",
            params: { visit: { area_id: foreign_area.id } },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Invalid area')
      expect(visit.reload.area_id).to be_nil
    end

    it 'rejects conflicting place_id and area_id' do
      place = create(:place, user: user, name: 'Coffee Shop')

      patch "/visits/#{visit.id}",
            params: { visit: { place_id: place.id, area_id: area.id } },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload).to have_attributes(place_id: nil, area_id: nil)
    end

    it 'confirms a suggested visit and uses the area name as its location label' do
      visit.update!(status: :suggested, name: 'before')

      patch "/visits/#{visit.id}",
            params: { visit: { area_id: area.id, status: 'confirmed' } }

      visit.reload
      expect(visit.status).to eq('confirmed')
      expect(visit.area_id).to be_nil
      expect(visit.place).to eq(LegacyAreaPlaceMapping.find_by!(area:).place)
      expect(visit).to have_attributes(name: 'before', location_label: 'Home')
    end

    it 'clears area_id when an empty value is sent' do
      visit.update!(area: area)
      expect(visit.reload.area_id).to eq(area.id)

      patch "/visits/#{visit.id}",
            params: { visit: { area_id: '' } }

      expect(visit.reload.area_id).to be_nil
    end

    it 'busts the timeline month cache for an area-only update' do
      month_start = visit.started_at.in_time_zone('Etc/UTC').to_date.beginning_of_month
      cache_key = Timeline::MonthSummary.cache_key_for(user, month_start)
      Rails.cache.write(cache_key, 'cached-value')

      patch "/visits/#{visit.id}",
            params: { visit: { area_id: area.id } }

      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end
end

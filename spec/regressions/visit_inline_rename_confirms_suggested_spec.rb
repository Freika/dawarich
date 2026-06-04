# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inline rename of a suggested visit', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'PATCH /visits/:id with only visit[name] on a suggested visit' do
    let!(:nearby_place_a) { create(:place, user:, name: 'Cafe A', latitude: 54.2905, longitude: 13.0948) }
    let!(:nearby_place_b) { create(:place, user:, name: 'Cafe B', latitude: 54.2906, longitude: 13.0949) }
    let(:visit) do
      v = create(:visit, user:, status: :suggested, name: 'Visit')
      v.update!(place: nearby_place_a)
      v
    end

    before do
      create(:place_visit, visit:, place: nearby_place_a)
      create(:place_visit, visit:, place: nearby_place_b)
    end

    it 'sets visit.name to the typed value' do
      patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream

      expect(visit.reload.name).to eq('My Coffee Spot')
    end

    it 'does NOT confirm the visit — status stays suggested' do
      patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream

      expect(visit.reload.status).to eq('suggested')
    end

    it 'does not create a new Place or change place_id' do
      original_place_id = visit.place_id

      expect do
        patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.place_id).to eq(original_place_id)
    end
  end

  describe 'PATCH /visits/:id with only visit[name] on a confirmed visit' do
    let(:visit) { create(:visit, user:, status: :confirmed, name: 'Old Name') }

    it 'updates the name without creating a Place or changing status' do
      expect do
        patch visit_url(visit), params: { visit: { name: 'Edited Name' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.name).to eq('Edited Name')
      expect(visit.reload.status).to eq('confirmed')
    end
  end

  describe 'PATCH /visits/:id with blank visit[name] on a suggested visit' do
    let(:visit) { create(:visit, user:, status: :suggested, name: 'Original') }

    it 'is a no-op for name and does not confirm or create a Place' do
      expect do
        patch visit_url(visit), params: { visit: { name: '   ' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.name).to eq('Original')
      expect(visit.reload.status).to eq('suggested')
    end
  end

  describe 'PATCH /visits/:id with rename on a suggested visit that has no resolvable center' do
    let(:visit) { create(:visit, user:, area: nil, place: nil, status: :suggested, name: 'Visit') }

    it 'renames the visit without error and leaves status suggested' do
      expect(visit.center).to eq([0, 0])

      expect do
        patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:ok)
      expect(visit.reload.name).to eq('My Coffee Spot')
      expect(visit.reload.status).to eq('suggested')
    end
  end

  describe 'PATCH /visits/:id with surrounding whitespace in visit[name] on a suggested visit' do
    let!(:nearby_place) { create(:place, user:, name: 'Cafe A', latitude: 54.2905, longitude: 13.0948) }
    let(:visit) do
      v = create(:visit, user:, status: :suggested, name: 'Visit')
      v.update!(place: nearby_place)
      v
    end

    before { create(:place_visit, visit:, place: nearby_place) }

    it 'stores the trimmed name on the visit and does not create a Place' do
      expect do
        patch visit_url(visit), params: { visit: { name: '  My Coffee Spot  ' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.name).to eq('My Coffee Spot')
      expect(visit.reload.status).to eq('suggested')
    end
  end

  describe 'PATCH /visits/:id picker confirm (place_id + status)' do
    let!(:nearby_place) { create(:place, user:, name: 'Cafe A', latitude: 54.2905, longitude: 13.0948) }
    let(:visit) { create(:visit, user:, status: :suggested, name: 'Visit') }

    before { create(:place_visit, visit:, place: nearby_place) }

    it 'still confirms via the picker without creating an extra Place' do
      expect do
        patch visit_url(visit),
              params: { visit: { place_id: nearby_place.id, status: :confirmed } },
              as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.place_id).to eq(nearby_place.id)
      expect(visit.reload.status).to eq('confirmed')
      expect(visit.reload.name).to eq('Cafe A')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::GeofenceEventsController, type: :controller do
  let(:user) { create(:user) }

  before { request.headers.merge!('Authorization' => "Bearer #{user.api_key}") }

  describe 'GET #index' do
    it 'lists user events ordered by occurred_at desc' do
      old_event = create(:geofence_event, user: user, occurred_at: 2.days.ago)
      new_event = create(:geofence_event, user: user, occurred_at: 1.hour.ago)
      get :index
      ids = JSON.parse(response.body).map { |e| e['id'] }
      expect(ids).to eq([new_event.id, old_event.id])
    end

    it 'filters by area_id' do
      area_a = create(:area, user: user)
      area_b = create(:area, user: user)
      match = create(:geofence_event, user: user, area: area_a)
      create(:geofence_event, user: user, area: area_b)
      get :index, params: { area_id: area_a.id }
      ids = JSON.parse(response.body).map { |e| e['id'] }
      expect(ids).to eq([match.id])
    end

    it 'does not return other users events' do
      other = create(:user)
      create(:geofence_event, user: other)
      get :index
      expect(JSON.parse(response.body)).to be_empty
    end

    it 'excludes synthetic events' do
      real = create(:geofence_event, user: user)
      create(:geofence_event, user: user, synthetic: true)
      get :index
      ids = JSON.parse(response.body).map { |e| e['id'] }
      expect(ids).to contain_exactly(real.id)
    end
  end
end

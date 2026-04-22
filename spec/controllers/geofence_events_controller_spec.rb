# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEventsController, type: :controller do
  render_views

  let(:user) { create(:user) }
  before { sign_in user }

  describe 'GET #index' do
    it 'renders' do
      create(:geofence_event, user: user)
      get :index
      expect(response).to have_http_status(:ok)
    end

    it 'filters by area_id and only shows matching area events' do
      a = create(:area, user: user)
      b = create(:area, user: user)
      match = create(:geofence_event, user: user, area: a)
      other = create(:geofence_event, user: user, area: b)
      get :index, params: { area_id: a.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("geofence_event_#{match.id}")
      expect(response.body).not_to include("geofence_event_#{other.id}")
    end

    it 'does not show events from other users' do
      other_user = create(:user)
      other_area = create(:area, user: other_user)
      other_event = create(:geofence_event, user: other_user, area: other_area)
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("geofence_event_#{other_event.id}")
    end
  end
end

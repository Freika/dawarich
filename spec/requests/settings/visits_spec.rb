# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Visits', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  describe 'GET /settings/visits' do
    it 'renders for any logged-in user' do
      get settings_visits_path
      expect(response).to have_http_status(:ok)
    end

    it 'requires authentication' do
      sign_out user
      get settings_visits_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'PATCH /settings/visits' do
    it 'updates the three permitted keys' do
      patch settings_visits_path, params: {
        settings: { visit_radius_meters: '75', visit_min_points: '4', visit_min_duration_minutes: '7' }
      }
      user.reload
      expect(user.safe_settings.visit_radius_meters).to eq(75)
      expect(user.safe_settings.visit_min_points).to eq(4)
      expect(user.safe_settings.visit_min_duration_minutes).to eq(7)
    end

    it 'ignores params other than the three permitted keys' do
      patch settings_visits_path, params: {
        settings: { visit_radius_meters: '60', admin: 'true', random_key: 'x' }
      }
      user.reload
      expect(user.settings.keys).not_to include('admin', 'random_key')
    end

    it 'redirects on success' do
      patch settings_visits_path, params: { settings: { visit_radius_meters: '60' } }
      expect(response).to redirect_to(settings_visits_path)
    end
  end
end

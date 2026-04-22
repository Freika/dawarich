# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/visits redirect', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /visits' do
    it 'redirects to /map timeline with confirmed status by default' do
      get '/visits'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to include('/map')
      expect(response.location).to include('panel=timeline')
      expect(response.location).to include('date=today')
      expect(response.location).to include('status=confirmed')
    end

    it 'preserves status=suggested when redirecting' do
      get '/visits', params: { status: 'suggested' }

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to include('panel=timeline')
      expect(response.location).to include('date=today')
      expect(response.location).to include('status=suggested')
    end

    it 'preserves status=declined when redirecting' do
      get '/visits', params: { status: 'declined' }

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to include('status=declined')
    end
  end
end

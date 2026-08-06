# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map routing', type: :request do
  let(:user) { create(:user) }

  describe 'GET /map' do
    before { sign_in user }

    it 'renders the MapLibre map' do
      get '/map'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('maps--maplibre')
    end
  end

  describe 'GET /map/v1' do
    it 'permanently redirects to the MapLibre map' do
      get '/map/v1'

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to end_with('/map/v2')
    end

    it 'preserves the query string' do
      get '/map/v1?start_at=2026-08-01T00:00:00'

      expect(response.headers['Location']).to end_with('/map/v2?start_at=2026-08-01T00:00:00')
    end
  end
end

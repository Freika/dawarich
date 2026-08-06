# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map routing', type: :request do
  let(:user) { create(:user) }

  describe 'GET /map' do
    it 'renders the MapLibre map when signed in' do
      sign_in user

      get '/map'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('maps--maplibre')
    end

    it 'redirects to sign-in when signed out' do
      get '/map'

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'GET /map/v1' do
    it 'permanently redirects to the MapLibre map' do
      get '/map/v1'

      expect(response).to have_http_status(:moved_permanently)
      expect(URI.parse(response.headers['Location']).path).to eq('/map/v2')
    end

    it 'preserves the query parameters' do
      get '/map/v1?start_at=2026-08-01T00:00:00'

      location = URI.parse(response.headers['Location'])
      expect(location.path).to eq('/map/v2')
      expect(Rack::Utils.parse_query(location.query)).to eq('start_at' => '2026-08-01T00:00:00')
    end
  end
end

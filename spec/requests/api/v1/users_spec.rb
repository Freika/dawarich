# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  describe 'GET /me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'returns success response' do
      get '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:success)
    end

    it 'returns only the keys and values stated in the serializer' do
      get '/api/v1/users/me', headers: headers

      json = JSON.parse(response.body, symbolize_names: true)

      expect(json.keys).to eq([:user])
      expect(json[:user].keys).to match_array(
        %i[email theme created_at updated_at settings]
      )
      expect(json[:user][:settings].keys).to match_array(%i[
        maps fog_of_war_meters meters_between_routes preferred_map_layer
        speed_colored_routes points_rendering_mode minutes_between_routes
        time_threshold_minutes merge_threshold_minutes live_map_enabled
        route_opacity immich_url photoprism_url visits_suggestions_enabled
        speed_color_scale fog_of_war_threshold
      ])
    end
  end
end

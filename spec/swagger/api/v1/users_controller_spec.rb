# frozen_string_literal: true

require 'swagger_helper'

describe 'Users API', type: :request do
  path '/api/v1/users/me' do
    get 'Returns the current user' do
      tags 'Users'
      consumes 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'

      response '200', 'user found' do
        let(:user) { create(:user) }
        let(:Authorization) { "Bearer #{user.api_key}" }

        schema type: :object,
               properties: {
                 user: {
                   type: :object,
                   properties: {
                     id: { type: :integer },
                     email: { type: :string },
                     created_at: { type: :string, format: 'date-time' },
                     updated_at: { type: :string, format: 'date-time' },
                     api_key: { type: :string },
                     theme: { type: :string },
                     settings: {
                       type: :object,
                       properties: {
                         immich_url: { type: :string },
                         route_opacity: { type: :string },
                         immich_api_key: { type: :string },
                         live_map_enabled: { type: :boolean },
                         fog_of_war_meters: { type: :string },
                         preferred_map_layer: { type: :string },
                         speed_colored_routes: { type: :boolean },
                         meters_between_routes: { type: :string },
                         points_rendering_mode: { type: :string },
                         minutes_between_routes: { type: :string },
                         time_threshold_minutes: { type: :string },
                         merge_threshold_minutes: { type: :string },
                         speed_colored_polylines: { type: :boolean }
                       }
                     },
                     admin: { type: :boolean }
                   }
                 }
               }

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body)
            }
          }
        end

        run_test!
      end
    end
  end
end

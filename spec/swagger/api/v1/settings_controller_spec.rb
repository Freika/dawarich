# frozen_string_literal: true

require 'swagger_helper'

describe 'Settings API', type: :request do
  path '/api/v1/settings' do
    patch 'Updates user settings' do
      request_body_example value: {
        'settings': {
          'route_opacity': 0.3,
          'meters_between_routes': 100,
          'minutes_between_routes': 100,
          'fog_of_war_meters': 100,
          'time_threshold_minutes': 100,
          'merge_threshold_minutes': 100
        }
      }
      tags 'Settings'
      consumes 'application/json'
      parameter name: :settings, in: :body, schema: {
        type: :object,
        properties: {
          route_opacity: {
            type: :number,
            example: 0.3,
            description: 'the opacity of the route, float between 0 and 1'
          },
          meters_between_routes: {
            type: :number,
            example: 100,
            description: 'the distance between routes in meters'
          },
          minutes_between_routes: {
            type: :number,
            example: 100,
            description: 'the time between routes in minutes'
          },
          fog_of_war_meters: {
            type: :number,
            example: 100,
            description: 'the fog of war distance in meters'
          }
        },
        optional: %w[route_opacity meters_between_routes minutes_between_routes fog_of_war_meters
                     time_threshold_minutes merge_threshold_minutes]
      }
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'settings updated' do
        let(:settings) { { settings: { route_opacity: 0.3 } } }
        let(:api_key)  { create(:user).api_key }

        run_test!
      end
    end

    get 'Retrieves user settings' do
      tags 'Settings'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'settings found' do
        schema type: :object,
               properties: {
                 settings: {
                   type: :object,
                   properties: {
                     route_opacity: {
                       type: :string,
                       example: 0.3,
                       description: 'the opacity of the route, float between 0 and 1'
                     },
                     meters_between_routes: {
                       type: :string,
                       example: 100,
                       description: 'the distance between routes in meters'
                     },
                     minutes_between_routes: {
                       type: :string,
                       example: 100,
                       description: 'the time between routes in minutes'
                     },
                     fog_of_war_meters: {
                       type: :string,
                       example: 100,
                       description: 'the fog of war distance in meters'
                     }
                   },
                   required: %w[route_opacity meters_between_routes minutes_between_routes fog_of_war_meters
                                time_threshold_minutes merge_threshold_minutes]
                 }
               }

        let(:user)     { create(:user) }
        let(:settings) { { settings: user.settings } }
        let(:api_key)  { user.api_key }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

describe 'Settings API', type: :request do
  path '/api/v1/settings' do
    patch 'Updates user settings' do
      request_body_example value: {
        'settings': {
          'route_opacity': 60,
          'meters_between_routes': 500,
          'minutes_between_routes': 30,
          'fog_of_war_meters': 50,
          'time_threshold_minutes': 30,
          'merge_threshold_minutes': 15,
          'preferred_map_layer': 'OpenStreetMap',
          'speed_colored_routes': false,
          'points_rendering_mode': 'raw',
          'live_map_enabled': true,
          'immich_url': 'https://immich.example.com',
          'immich_api_key': 'your-immich-api-key',
          'photoprism_url': 'https://photoprism.example.com',
          'photoprism_api_key': 'your-photoprism-api-key',
          'speed_color_scale': 'viridis',
          'fog_of_war_threshold': 100
        }
      }
      tags 'Settings'
      consumes 'application/json'
      parameter name: :settings, in: :body, schema: {
        type: :object,
        properties: {
          route_opacity: {
            type: :number,
            example: 60,
            description: 'Route opacity percentage (0-100)'
          },
          meters_between_routes: {
            type: :number,
            example: 500,
            description: 'Minimum distance between routes in meters'
          },
          minutes_between_routes: {
            type: :number,
            example: 30,
            description: 'Minimum time between routes in minutes'
          },
          fog_of_war_meters: {
            type: :number,
            example: 50,
            description: 'Fog of war radius in meters'
          },
          time_threshold_minutes: {
            type: :number,
            example: 30,
            description: 'Time threshold for grouping points in minutes'
          },
          merge_threshold_minutes: {
            type: :number,
            example: 15,
            description: 'Threshold for merging nearby points in minutes'
          },
          preferred_map_layer: {
            type: :string,
            example: 'OpenStreetMap',
            description: 'Preferred map layer/tile provider'
          },
          speed_colored_routes: {
            type: :boolean,
            example: false,
            description: 'Whether to color routes based on speed'
          },
          points_rendering_mode: {
            type: :string,
            example: 'raw',
            description: 'How to render points on the map (raw, heatmap, etc.)'
          },
          live_map_enabled: {
            type: :boolean,
            example: true,
            description: 'Whether live map updates are enabled'
          },
          immich_url: {
            type: :string,
            example: 'https://immich.example.com',
            description: 'Immich server URL for photo integration'
          },
          immich_api_key: {
            type: :string,
            example: 'your-immich-api-key',
            description: 'API key for Immich photo service'
          },
          photoprism_url: {
            type: :string,
            example: 'https://photoprism.example.com',
            description: 'PhotoPrism server URL for photo integration'
          },
          photoprism_api_key: {
            type: :string,
            example: 'your-photoprism-api-key',
            description: 'API key for PhotoPrism photo service'
          },
          speed_color_scale: {
            type: :string,
            example: 'viridis',
            description: 'Color scale for speed-colored routes'
          },
          fog_of_war_threshold: {
            type: :number,
            example: 100,
            description: 'Fog of war threshold value'
          }
        }
      }
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'settings updated' do
        let(:settings) { { settings: { route_opacity: 60 } } }
        let(:api_key)  { create(:user).api_key }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:settings) { { settings: { route_opacity: 60 } } }

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
                       type: :number,
                       example: 60,
                       description: 'Route opacity percentage (0-100)'
                     },
                     meters_between_routes: {
                       oneOf: [
                         { type: :number },
                         { type: :string }
                       ],
                       example: 500,
                       description: 'Minimum distance between routes in meters'
                     },
                     minutes_between_routes: {
                       oneOf: [
                         { type: :number },
                         { type: :string }
                       ],
                       example: 30,
                       description: 'Minimum time between routes in minutes'
                     },
                     fog_of_war_meters: {
                       oneOf: [
                         { type: :number },
                         { type: :string }
                       ],
                       example: 50,
                       description: 'Fog of war radius in meters'
                     },
                     time_threshold_minutes: {
                       oneOf: [
                         { type: :number },
                         { type: :string }
                       ],
                       example: 30,
                       description: 'Time threshold for grouping points in minutes'
                     },
                     merge_threshold_minutes: {
                       oneOf: [
                         { type: :number },
                         { type: :string }
                       ],
                       example: 15,
                       description: 'Threshold for merging nearby points in minutes'
                     },
                     preferred_map_layer: {
                       type: :string,
                       example: 'OpenStreetMap',
                       description: 'Preferred map layer/tile provider'
                     },
                     speed_colored_routes: {
                       type: :boolean,
                       example: false,
                       description: 'Whether to color routes based on speed'
                     },
                     points_rendering_mode: {
                       type: :string,
                       example: 'raw',
                       description: 'How to render points on the map (raw, heatmap, etc.)'
                     },
                     live_map_enabled: {
                       type: :boolean,
                       example: true,
                       description: 'Whether live map updates are enabled'
                     },
                     immich_url: {
                       oneOf: [
                         { type: :string },
                         { type: :null }
                       ],
                       example: 'https://immich.example.com',
                       description: 'Immich server URL for photo integration'
                     },
                     immich_api_key: {
                       oneOf: [
                         { type: :string },
                         { type: :null }
                       ],
                       example: 'your-immich-api-key',
                       description: 'API key for Immich photo service'
                     },
                     photoprism_url: {
                       oneOf: [
                         { type: :string },
                         { type: :null }
                       ],
                       example: 'https://photoprism.example.com',
                       description: 'PhotoPrism server URL for photo integration'
                     },
                     photoprism_api_key: {
                       oneOf: [
                         { type: :string },
                         { type: :null }
                       ],
                       example: 'your-photoprism-api-key',
                       description: 'API key for PhotoPrism photo service'
                     },
                     speed_color_scale: {
                       oneOf: [
                         { type: :string },
                         { type: :null }
                       ],
                       example: 'viridis',
                       description: 'Color scale for speed-colored routes'
                     },
                     fog_of_war_threshold: {
                       oneOf: [
                         { type: :number },
                         { type: :string },
                         { type: :null }
                       ],
                       example: 100,
                       description: 'Fog of war threshold value'
                     }
                   }
                 }
               }

        let(:user)     { create(:user) }
        let(:settings) { { settings: user.settings } }
        let(:api_key)  { user.api_key }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/settings/transportation_recalculation_status' do
    get 'Retrieves transportation mode recalculation status' do
      tags 'Settings'
      description 'Returns the current status of transportation mode recalculation for all tracks'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'status found' do
        schema type: :object,
               properties: {
                 status: { type: :string, nullable: true, description: 'Current recalculation status' },
                 total_tracks: { type: :integer, nullable: true, description: 'Total number of tracks to process' },
                 processed_tracks: { type: :integer, nullable: true, description: 'Number of tracks processed so far' },
                 started_at: { type: :string, nullable: true, description: 'When recalculation started' },
                 completed_at: { type: :string, nullable: true, description: 'When recalculation completed' },
                 error_message: { type: :string, nullable: true, description: 'Error message if recalculation failed' }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

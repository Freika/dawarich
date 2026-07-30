# frozen_string_literal: true

require 'swagger_helper'

describe 'Mobile Settings API', type: :request do
  path '/api/v1/settings/mobile' do
    get 'Retrieves mobile app settings' do
      tags 'Settings'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'mobile settings found' do
        schema type: :object,
               properties: {
                 settings: {
                   type: :object,
                   properties: {
                     tracking_mode: { type: :string, example: 'precise', enum: %w[precise significant] },
                     tracking_visits: { type: :boolean, example: true },
                     track_visits_independently: { type: :boolean, example: false },
                     auto_start: { type: :boolean, example: true },
                     distance_filter: { type: :number, example: 100 },
                     time_filter: { type: :number, example: 10 },
                     track_break: { type: :number, example: 30 },
                     accuracy: { type: :number, example: 3 },
                     show_background_location_indicator: { type: :boolean, example: true },
                     upload_automatically: { type: :boolean, example: true },
                     upload_all_on_tracking_stop: { type: :boolean, example: false },
                     batch_size: { type: :number, example: 100 }
                   }
                 },
                 updated_at: { type: :string, nullable: true, example: '2026-07-01T10:00:00Z' },
                 status: { type: :string, example: 'success' }
               }

        let(:api_key) { create(:user).api_key }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    patch 'Updates mobile app settings' do
      request_body_example value: {
        'settings': {
          'tracking_mode': 'precise',
          'tracking_visits': true,
          'track_visits_independently': false,
          'auto_start': true,
          'distance_filter': 100,
          'time_filter': 10,
          'track_break': 30,
          'accuracy': 3,
          'show_background_location_indicator': true,
          'upload_automatically': true,
          'upload_all_on_tracking_stop': false,
          'batch_size': 100
        }
      }
      tags 'Settings'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :settings, in: :body, schema: {
        type: :object,
        properties: {
          tracking_mode: {
            type: :string,
            example: 'precise',
            enum: %w[precise significant],
            description: 'Location tracking mode'
          },
          tracking_visits: {
            type: :boolean,
            example: true,
            description: 'Whether visit tracking is enabled'
          },
          track_visits_independently: {
            type: :boolean,
            example: false,
            description: 'Whether visits are tracked independently of route tracking'
          },
          auto_start: {
            type: :boolean,
            example: true,
            description: 'Whether tracking starts automatically'
          },
          distance_filter: {
            type: :number,
            example: 100,
            description: 'Minimum distance between tracked points in meters (1-10000)'
          },
          time_filter: {
            type: :number,
            example: 10,
            description: 'Minimum time between tracked points in seconds (1-3600)'
          },
          track_break: {
            type: :number,
            example: 30,
            description: 'Minutes of inactivity before a track is split (1-1440)'
          },
          accuracy: {
            type: :number,
            example: 3,
            description: 'Location accuracy level (1-6)'
          },
          show_background_location_indicator: {
            type: :boolean,
            example: true,
            description: 'Whether the OS background-location indicator is shown (iOS)'
          },
          upload_automatically: {
            type: :boolean,
            example: true,
            description: 'Whether points upload automatically while tracking'
          },
          upload_all_on_tracking_stop: {
            type: :boolean,
            example: false,
            description: 'Whether pending points upload when tracking stops'
          },
          batch_size: {
            type: :number,
            example: 100,
            description: 'Number of points per automatic upload batch (1-1000)'
          }
        }
      }

      response '200', 'mobile settings updated' do
        let(:api_key) { create(:user).api_key }
        let(:settings) { { settings: { tracking_mode: 'significant', batch_size: 50 } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:settings) { { settings: { tracking_mode: 'significant' } } }

        run_test!
      end
    end
  end
end

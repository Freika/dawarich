# frozen_string_literal: true

require 'swagger_helper'

describe 'Traccar Points API', type: :request do
  path '/api/v1/traccar/points' do
    post 'Creates a point' do
      request_body_example value: {
        device_id: 'iphone-jane',
        location: {
          timestamp: '2026-04-23T12:34:56Z',
          latitude: 52.52,
          longitude: 13.405,
          accuracy: 5,
          speed: 1.4,
          heading: 90,
          altitude: 42,
          is_moving: true,
          odometer: 1200,
          event: 'motionchange'
        },
        battery: { level: 0.85, is_charging: true },
        activity: { type: 'walking' }
      }
      tags 'Points'
      consumes 'application/json'
      parameter name: :point, in: :body, schema: {
        type: :object,
        properties: {
          device_id: { type: :string, description: 'Tracker / device identifier' },
          location: {
            type: :object,
            properties: {
              timestamp: { type: :string, description: 'ISO 8601 timestamp of the location fix' },
              latitude:  { type: :number, description: 'Latitude in decimal degrees' },
              longitude: { type: :number, description: 'Longitude in decimal degrees' },
              accuracy:  { type: :number, description: 'Horizontal accuracy in meters' },
              speed:     { type: :number, description: 'Speed in meters per second' },
              heading:   { type: :number, description: 'Bearing in degrees (0-360)' },
              altitude:  { type: :number, description: 'Altitude in meters' },
              is_moving: { type: :boolean, description: 'Whether the device was moving at the time of the fix' },
              odometer:  { type: :number, description: 'Cumulative distance traveled in meters' },
              event:     { type: :string,
description: 'Event type that produced the fix (e.g. motionchange, heartbeat)' }
            },
            required: %w[latitude longitude timestamp]
          },
          battery: {
            type: :object,
            properties: {
              level:       { type: :number, description: 'Battery level as a 0-1 fraction' },
              is_charging: { type: :boolean, description: 'Whether the device is currently charging' }
            }
          },
          activity: {
            type: :object,
            properties: {
              type: { type: :string, description: 'Detected activity (walking, running, in_vehicle, ...)' }
            }
          }
        },
        required: %w[device_id location]
      }

      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'Point created' do
        let(:point) do
          {
            device_id: 'iphone-jane',
            location: {
              timestamp: '2026-04-23T12:34:56Z',
              latitude: 52.52,
              longitude: 13.405,
              accuracy: 5,
              speed: 1.4,
              altitude: 42
            },
            battery: { level: 0.85, is_charging: true },
            activity: { type: 'walking' }
          }
        end
        let(:api_key) { create(:user).api_key }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:point) { { device_id: 'x' } }
        let(:api_key) { nil }

        run_test!
      end
    end
  end
end

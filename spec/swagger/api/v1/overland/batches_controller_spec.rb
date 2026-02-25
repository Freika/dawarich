# frozen_string_literal: true

require 'swagger_helper'

describe 'Overland Batches API', type: :request do
  path '/api/v1/overland/batches' do
    post 'Creates a batch of points' do
      request_body_example value: {
        locations: [
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [13.356718, 52.502397]
            },
            properties: {
              timestamp: '2021-06-01T12:00:00Z',
              altitude: 0,
              speed: 0,
              horizontal_accuracy: 0,
              vertical_accuracy: 0,
              motion: [],
              pauses: false,
              activity: 'unknown',
              desired_accuracy: 0,
              deferred: 0,
              significant_change: 'unknown',
              locations_in_payload: 1,
              device_id: 'iOS device #166',
              unique_id: '1234567890',
              wifi: 'unknown',
              battery_state: 'unknown',
              battery_level: 0
            }
          }
        ]
      }
      tags 'Batches'
      consumes 'application/json'
      parameter name: :locations, in: :body, schema: {
        type: :object,
        properties: {
          locations: {
            type: :array,
            items: {
              type: :object,
              properties: {
                type: { type: :string, example: 'Feature' },
                geometry: {
                  type: :object,
                  properties: {
                    type: { type: :string, example: 'Point' },
                    coordinates: {
                      type: :array,
                      items: { type: :number },
                      example: [13.356718, 52.502397]
                    }
                  }
                },
                properties: {
                  type: :object,
                  properties: {
                    timestamp: {
                      type: :string,
                      example: '2021-06-01T12:00:00Z',
                      description: 'Timestamp in ISO 8601 format'
                    },
                    altitude: {
                      type: :number,
                      example: 0,
                      description: 'Altitude in meters'
                    },
                    speed: {
                      type: :number,
                      example: 0,
                      description: 'Speed in meters per second'
                    },
                    horizontal_accuracy: {
                      type: :number,
                      example: 0,
                      description: 'Horizontal accuracy in meters'
                    },
                    vertical_accuracy: {
                      type: :number,
                      example: 0,
                      description: 'Vertical accuracy in meters'
                    },
                    motion: {
                      type: :array,
                      items: { type: :string },
                      example: %w[walking running driving cycling stationary],
                      description: 'Motion type, for example: automotive_navigation, fitness, other_navigation or other'
                    },
                    activity: {
                      type: :string,
                      example: 'unknown',
                      description: 'Activity type, e.g.: automotive_navigation, fitness, ' \
                                   'other_navigation or other'
                    },
                    desired_accuracy: {
                      type: :number,
                      example: 0,
                      description: 'Desired accuracy in meters'
                    },
                    deferred: {
                      type: :number,
                      example: 0,
                      description: 'the distance in meters to defer location updates'
                    },
                    significant_change: {
                      type: :string,
                      example: 'disabled',
                      description: 'a significant change mode, disabled, enabled or exclusive'
                    },
                    locations_in_payload: {
                      type: :number,
                      example: 1,
                      description: 'the number of locations in the payload'
                    },
                    device_id: {
                      type: :string,
                      example: 'iOS device #166',
                      description: 'the device id'
                    },
                    unique_id: {
                      type: :string,
                      example: '1234567890',
                      description: 'the device\'s Unique ID as set by Apple'
                    },
                    wifi: {
                      type: :string,
                      example: 'unknown',
                      description: 'the WiFi network name'
                    },
                    battery_state: {
                      type: :string,
                      example: 'unknown',
                      description: 'the battery state, unknown, unplugged, charging or full'
                    },
                    battery_level: {
                      type: :number,
                      example: 0,
                      description: 'the battery level percentage, from 0 to 1'
                    }
                  }
                }
              },
              required: %w[geometry properties]
            }
          }
        }
      }

      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '201', 'Batch of points created' do
        let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:params) { json }
        let(:locations) { params['locations'] }
        let(:api_key) { create(:user).api_key }

        after do |example|
          content = example.metadata[:response][:content] || {}
          example.metadata[:response][:content] = content.merge(
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          )
        end

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:params) { json }
        let(:locations) { params['locations'] }
        let(:api_key) { nil }

        run_test!
      end
    end
  end
end

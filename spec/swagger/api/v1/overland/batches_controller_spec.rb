# frozen_string_literal: true

require 'swagger_helper'

describe 'Batches API', type: :request do
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
              device_id: 'Swagger',
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
          type: { type: :string },
          geometry: {
            type: :object,
            properties: {
              type: { type: :string },
              coordinates: { type: :array }
            }
          },
          properties: {
            type: :object,
            properties: {
              timestamp: { type: :string },
              altitude: { type: :number },
              speed: { type: :number },
              horizontal_accuracy: { type: :number },
              vertical_accuracy: { type: :number },
              motion: { type: :array },
              pauses: { type: :boolean },
              activity: { type: :string },
              desired_accuracy: { type: :number },
              deferred: { type: :number },
              significant_change: { type: :string },
              locations_in_payload: { type: :number },
              device_id: { type: :string },
              wifi: { type: :string },
              battery_state: { type: :string },
              battery_level: { type: :number }
            }
          },
        required: %w[geometry properties]
        }
      }

      response '201', 'Batch of points created' do
        let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:params) { json }
        let(:locations) { params['locations'] }

        run_test!
      end
    end
  end
end

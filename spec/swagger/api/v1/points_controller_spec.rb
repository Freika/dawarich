# frozen_string_literal: true

require 'swagger_helper'

describe 'Points API', type: :request do
  path '/api/v1/points' do
    get 'Retrieves all points' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string,
                description: 'Start date (i.e. 2024-02-03T13:00:03Z or 2024-02-03)'
      parameter name: :end_at, in: :query, type: :string,
                description: 'End date (i.e. 2024-02-03T13:00:03Z or 2024-02-03)'
      parameter name: :page, in: :query, type: :integer, required: false, description: 'Page number'
      parameter name: :per_page, in: :query, type: :integer, required: false, description: 'Number of points per page'
      parameter name: :order, in: :query, type: :string, required: false,
                description: 'Order of points, valid values are `asc` or `desc`'
      response '200', 'points found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:                { type: :integer },
                   battery_status:    { type: :number },
                   ping:              { type: :number },
                   battery:           { type: :number },
                   tracker_id:        { type: :string },
                   topic:             { type: :string },
                   altitude:          { type: :number },
                   longitude:         { type: :number },
                   velocity:          { type: :number },
                   trigger:           { type: :string },
                   bssid:             { type: :string },
                   ssid:              { type: :string },
                   connection:        { type: :string },
                   vertical_accuracy: { type: :number },
                   accuracy:          { type: :number },
                   timestamp:         { type: :number },
                   latitude:          { type: :number },
                   mode:              { type: :number },
                   inrids:            { type: :array, items: { type: :string } },
                   in_regions:        { type: :array, items: { type: :string } },
                   raw_data:          { type: :string },
                   import_id:         { type: :string },
                   city:              { type: :string },
                   country:           { type: :string },
                   created_at:        { type: :string },
                   updated_at:        { type: :string },
                   user_id:           { type: :integer },
                   geodata:           { type: :string },
                   visit_id:          { type: :string }
                 }
               }

        let(:user)      { create(:user) }
        let(:areas)     { create_list(:area, 3, user:) }
        let(:api_key)   { user.api_key }
        let(:start_at)  { Time.zone.now - 1.day }
        let(:end_at)    { Time.zone.now }
        let(:points) do
          (1..10).map do |i|
            create(:point, user:, timestamp: 2.hours.ago + i.minutes)
          end
        end

        run_test!
      end
    end

    post 'Creates a batch of points' do
      request_body_example value: {
        locations: [
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [-122.40530871, 37.74430413]
            },
            properties: {
              battery_state: 'full',
              battery_level: 0.7,
              wifi: 'dawarich_home',
              timestamp: '2025-01-17T21:03:01Z',
              horizontal_accuracy: 5,
              vertical_accuracy: -1,
              altitude: 0,
              speed: 92.088,
              speed_accuracy: 0,
              course: 27.07,
              course_accuracy: 0,
              track_id: '799F32F5-89BB-45FB-A639-098B1B95B09F',
              device_id: '8D5D4197-245B-4619-A88B-2049100ADE46'
            }
          }
        ]
      }
      tags 'Points'
      consumes 'application/json'
      parameter name: :locations, in: :body, schema: {
        type: :object,
        properties: {
          locations: {
            type: :array,
            items: {
              type: :object,
              properties: {
                type: { type: :string },
                geometry: {
                  type: :object,
                  properties: {
                    type: {
                      type: :string,
                      example: 'Point',
                      description: 'the geometry type, always Point'
                    },
                    coordinates: {
                      type: :array,
                      items: {
                        type: :number,
                        example: [-122.40530871, 37.74430413],
                        description: 'the coordinates of the point, longitude and latitude'
                      }
                    }
                  }
                },
                properties: {
                  type: :object,
                  properties: {
                    timestamp: {
                      type: :string,
                      example: '2025-01-17T21:03:01Z',
                      description: 'the timestamp of the point'
                    },
                    horizontal_accuracy: {
                      type: :number,
                      example: 5,
                      description: 'the horizontal accuracy of the point in meters'
                    },
                    vertical_accuracy: {
                      type: :number,
                      example: -1,
                      description: 'the vertical accuracy of the point in meters'
                    },
                    altitude: {
                      type: :number,
                      example: 0,
                      description: 'the altitude of the point in meters'
                    },
                    speed: {
                      type: :number,
                      example: 92.088,
                      description: 'the speed of the point in meters per second'
                    },
                    speed_accuracy: {
                      type: :number,
                      example: 0,
                      description: 'the speed accuracy of the point in meters per second'
                    },
                    course_accuracy: {
                      type: :number,
                      example: 0,
                      description: 'the course accuracy of the point in degrees'
                    },
                    track_id: {
                      type: :string,
                      example: '799F32F5-89BB-45FB-A639-098B1B95B09F',
                      description: 'the track id of the point set by the device'
                    },
                    device_id: {
                      type: :string,
                      example: '8D5D4197-245B-4619-A88B-2049100ADE46',
                      description: 'the device id of the point set by the device'
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

      response '200', 'Batch of points being processed' do
        let(:file_path) { 'spec/fixtures/files/points/geojson_example.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:locations) { json }
        let(:api_key) { create(:user).api_key }

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:file_path) { 'spec/fixtures/files/points/geojson_example.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:locations) { json }
        let(:api_key) { 'invalid_api_key' }

        run_test!
      end
    end
  end

  path '/api/v1/points/{id}' do
    delete 'Deletes a point' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :id, in: :path, type: :string, required: true, description: 'Point ID'

      response '200', 'point deleted' do
        let(:user)    { create(:user) }
        let(:point)   { create(:point, user:) }
        let(:api_key) { user.api_key }
        let(:id)      { point.id }

        run_test!
      end
    end
  end
end

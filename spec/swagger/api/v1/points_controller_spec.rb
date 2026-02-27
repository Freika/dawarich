# frozen_string_literal: true

require 'swagger_helper'

describe 'Points API', type: :request do
  path '/api/v1/points' do
    get 'Retrieves all points' do
      tags 'Points'
      description 'Returns paginated location points for the authenticated user, optionally filtered by date range'
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
                   id: { type: :integer, description: 'Unique point identifier' },
                   battery_status: { type: :number, nullable: true, description: 'Battery status code' },
                   ping: { type: :number, nullable: true, description: 'Ping value' },
                   battery: { type: :number, nullable: true, description: 'Battery level' },
                   tracker_id: { type: :string, nullable: true, description: 'Tracker identifier' },
                   topic: { type: :string, nullable: true, description: 'MQTT topic' },
                   altitude: { type: :number, nullable: true, description: 'Altitude in meters' },
                   longitude: { type: :number, description: 'Longitude coordinate' },
                   velocity: { type: :number, nullable: true, description: 'Velocity in km/h' },
                   trigger: { type: :string, nullable: true, description: 'Trigger type' },
                   bssid: { type: :string, nullable: true, description: 'WiFi access point MAC address' },
                   ssid: { type: :string, nullable: true, description: 'WiFi network name' },
                   connection: { type: :string, nullable: true, description: 'Connection type (w=wifi, m=mobile)' },
                   vertical_accuracy: { type: :number, nullable: true, description: 'Vertical accuracy in meters' },
                   accuracy: { type: :number, nullable: true, description: 'Horizontal accuracy in meters' },
                   timestamp: { type: :number, description: 'Unix timestamp of the point' },
                   latitude: { type: :number, description: 'Latitude coordinate' },
                   mode: { type: :number, nullable: true, description: 'Tracking mode' },
                   inrids: { type: :array, items: { type: :string }, nullable: true, description: 'Region IDs' },
                   in_regions: { type: :array, items: { type: :string }, nullable: true, description: 'Region names' },
                   raw_data: { type: :string, nullable: true, description: 'Raw data from the tracking device' },
                   import_id: { type: :string, nullable: true, description: 'Import ID if point was imported' },
                   city: { type: :string, nullable: true, description: 'Reverse-geocoded city name' },
                   country: { type: :string, nullable: true, description: 'Reverse-geocoded country name' },
                   created_at: { type: :string, format: 'date-time', description: 'Record creation timestamp' },
                   updated_at: { type: :string, format: 'date-time', description: 'Record last update timestamp' },
                   user_id: { type: :integer, description: 'Owning user ID' },
                   geodata: { type: :string, nullable: true, description: 'Reverse-geocoded geodata' },
                   visit_id: { type: :string, nullable: true, description: 'Associated visit ID' }
                 }
               }

        header 'X-Current-Page', schema: { type: :integer }, description: 'Current page number'
        header 'X-Total-Pages', schema: { type: :integer }, description: 'Total number of pages'

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:start_at) { Time.zone.now - 1.day }
        let(:end_at) { Time.zone.now }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.zone.now.iso8601 }

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

        after { |example| SwaggerResponseExample.capture(example, response) }

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
    parameter name: :id, in: :path, type: :string, required: true, description: 'Point ID'

    patch 'Updates a point' do
      tags 'Points'
      description 'Updates the latitude and/or longitude of a point'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :point, in: :body, schema: {
        type: :object,
        properties: {
          point: {
            type: :object,
            properties: {
              latitude: { type: :number, description: 'Updated latitude coordinate' },
              longitude: { type: :number, description: 'Updated longitude coordinate' }
            }
          }
        }
      }

      response '200', 'point updated' do
        let(:user) { create(:user) }
        let(:existing_point) { create(:point, user:) }
        let(:api_key) { user.api_key }
        let(:id) { existing_point.id }
        let(:point) { { point: { latitude: 52.52, longitude: 13.405 } } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'invalid request' do
        let(:user) { create(:user) }
        let(:existing_point) { create(:point, user:) }
        let(:api_key) { user.api_key }
        let(:id) { existing_point.id }
        let(:point) { { point: { latitude: nil } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:point).id }
        let(:point) { { point: { latitude: 52.52 } } }

        run_test!
      end
    end

    delete 'Deletes a point' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'point deleted' do
        schema type: :object,
               properties: {
                 message: { type: :string, description: 'Confirmation message' }
               }

        let(:user) { create(:user) }
        let(:point) { create(:point, user:) }
        let(:api_key) { user.api_key }
        let(:id) { point.id }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:point).id }

        run_test!
      end
    end
  end

  path '/api/v1/points/bulk_destroy' do
    delete 'Bulk deletes points' do
      tags 'Points'
      description 'Deletes multiple points by their IDs'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :bulk_params, in: :body, schema: {
        type: :object,
        properties: {
          point_ids: {
            type: :array,
            items: { type: :integer },
            description: 'Array of point IDs to delete'
          }
        },
        required: %w[point_ids]
      }

      response '200', 'points deleted' do
        schema type: :object,
               properties: {
                 message: { type: :string, description: 'Confirmation message' },
                 count: { type: :integer, description: 'Number of points deleted' }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:point1) { create(:point, user:) }
        let(:point2) { create(:point, user:) }
        let(:bulk_params) { { point_ids: [point1.id, point2.id] } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'no points selected' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:bulk_params) { { point_ids: [] } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:bulk_params) { { point_ids: [1] } }

        run_test!
      end
    end
  end
end

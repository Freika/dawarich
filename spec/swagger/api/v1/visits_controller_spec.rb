# frozen_string_literal: true

require 'swagger_helper'

describe 'Visits API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:place) { create(:place) }
  let(:test_visit) { create(:visit, user: user, place: place) }

  path '/api/v1/visits' do
    get 'List visits' do
      tags 'Visits'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :start_at, in: :query, type: :string, required: false, description: 'Start date (ISO 8601)'
      parameter name: :end_at, in: :query, type: :string, required: false, description: 'End date (ISO 8601)'
      parameter name: :selection, in: :query, type: :string, required: false,
                description: 'Set to "true" for area-based search'
      parameter name: :sw_lat, in: :query, type: :number, required: false,
                description: 'Southwest latitude for area search'
      parameter name: :sw_lng, in: :query, type: :number, required: false,
                description: 'Southwest longitude for area search'
      parameter name: :ne_lat, in: :query, type: :number, required: false,
                description: 'Northeast latitude for area search'
      parameter name: :ne_lng, in: :query, type: :number, required: false,
                description: 'Northeast longitude for area search'

      response '200', 'visits found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:start_at) { 1.week.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   name: { type: :string },
                   status: { type: :string, enum: %w[suggested confirmed declined] },
                   started_at: { type: :string, format: :datetime },
                   ended_at: { type: :string, format: :datetime },
                   duration: { type: :integer, description: 'Duration in minutes' },
                   place: {
                     type: :object,
                     properties: {
                       id: { type: :integer },
                       name: { type: :string },
                       latitude: { type: :number },
                       longitude: { type: :number },
                       city: { type: :string },
                       country: { type: :string }
                     }
                   }
                 },
                 required: %w[id name status started_at ended_at duration]
               }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        run_test!
      end
    end

    post 'Create visit' do
      tags 'Visits'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :visit, in: :body, schema: {
        type: :object,
        properties: {
          visit: {
            type: :object,
            properties: {
              name: { type: :string },
              latitude: { type: :number },
              longitude: { type: :number },
              started_at: { type: :string, format: :datetime },
              ended_at: { type: :string, format: :datetime }
            },
            required: %w[name latitude longitude started_at ended_at]
          }
        }
      }

      response '200', 'visit created' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:visit) do
          {
            visit: {
              name: 'Test Visit',
              latitude: 52.52,
              longitude: 13.405,
              started_at: '2023-12-01T10:00:00Z',
              ended_at: '2023-12-01T12:00:00Z'
            }
          }
        end

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 status: { type: :string },
                 started_at: { type: :string, format: :datetime },
                 ended_at: { type: :string, format: :datetime },
                 duration: { type: :integer },
                 place: {
                   type: :object,
                   properties: {
                     id: { type: :integer },
                     name: { type: :string },
                     latitude: { type: :number },
                     longitude: { type: :number }
                   }
                 }
               }

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:visit) do
          {
            visit: {
              name: '',
              latitude: 52.52,
              longitude: 13.405,
              started_at: '2023-12-01T10:00:00Z',
              ended_at: '2023-12-01T12:00:00Z'
            }
          }
        end

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:visit) do
          {
            visit: {
              name: 'Test Visit',
              latitude: 52.52,
              longitude: 13.405,
              started_at: '2023-12-01T10:00:00Z',
              ended_at: '2023-12-01T12:00:00Z'
            }
          }
        end

        run_test!
      end
    end
  end

  path '/api/v1/visits/{id}' do
    patch 'Update visit' do
      tags 'Visits'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Visit ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :visit, in: :body, schema: {
        type: :object,
        properties: {
          visit: {
            type: :object,
            properties: {
              name: { type: :string },
              place_id: { type: :integer },
              status: { type: :string, enum: %w[suggested confirmed declined] }
            }
          }
        }
      }

      response '200', 'visit updated' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { test_visit.id }
        let(:visit) { { visit: { name: 'Updated Visit' } } }

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 status: { type: :string },
                 started_at: { type: :string, format: :datetime },
                 ended_at: { type: :string, format: :datetime },
                 duration: { type: :integer },
                 place: { type: :object }
               }

        run_test!
      end

      response '404', 'visit not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }
        let(:visit) { { visit: { name: 'Updated Visit' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { test_visit.id }
        let(:visit) { { visit: { name: 'Updated Visit' } } }

        run_test!
      end
    end

    delete 'Delete visit' do
      tags 'Visits'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Visit ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '204', 'visit deleted' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { test_visit.id }

        run_test!
      end

      response '404', 'visit not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { test_visit.id }

        run_test!
      end
    end
  end

  path '/api/v1/visits/{id}/possible_places' do
    get 'Get possible places for visit' do
      tags 'Visits'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Visit ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '200', 'possible places found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { test_visit.id }

        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   name: { type: :string },
                   latitude: { type: :number },
                   longitude: { type: :number },
                   city: { type: :string },
                   country: { type: :string }
                 }
               }

        run_test!
      end

      response '404', 'visit not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { test_visit.id }

        run_test!
      end
    end
  end

  path '/api/v1/visits/merge' do
    post 'Merge visits' do
      tags 'Visits'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :merge_params, in: :body, schema: {
        type: :object,
        properties: {
          visit_ids: {
            type: :array,
            items: { type: :integer },
            minItems: 2,
            description: 'Array of visit IDs to merge (minimum 2)'
          }
        },
        required: %w[visit_ids]
      }

      response '200', 'visits merged' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:visit1) { create(:visit, user: user) }
        let(:visit2) { create(:visit, user: user) }
        let(:merge_params) { { visit_ids: [visit1.id, visit2.id] } }

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 status: { type: :string },
                 started_at: { type: :string, format: :datetime },
                 ended_at: { type: :string, format: :datetime },
                 duration: { type: :integer },
                 place: { type: :object }
               }

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:merge_params) { { visit_ids: [test_visit.id] } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:merge_params) { { visit_ids: [test_visit.id] } }

        run_test!
      end
    end
  end

  path '/api/v1/visits/bulk_update' do
    post 'Bulk update visits' do
      tags 'Visits'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :bulk_params, in: :body, schema: {
        type: :object,
        properties: {
          visit_ids: {
            type: :array,
            items: { type: :integer },
            description: 'Array of visit IDs to update'
          },
          status: {
            type: :string,
            enum: %w[suggested confirmed declined],
            description: 'New status for the visits'
          }
        },
        required: %w[visit_ids status]
      }

      response '200', 'visits updated' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:visit1) { create(:visit, user: user, status: 'suggested') }
        let(:visit2) { create(:visit, user: user, status: 'suggested') }
        let(:bulk_params) { { visit_ids: [visit1.id, visit2.id], status: 'confirmed' } }

        schema type: :object,
               properties: {
                 message: { type: :string },
                 updated_count: { type: :integer }
               }

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:bulk_params) { { visit_ids: [test_visit.id], status: 'invalid_status' } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:bulk_params) { { visit_ids: [test_visit.id], status: 'confirmed' } }

        run_test!
      end
    end
  end
end

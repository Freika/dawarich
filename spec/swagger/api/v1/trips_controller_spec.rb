# frozen_string_literal: true

require 'swagger_helper'

describe 'Trips API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  trip_properties = {
    id: { type: :integer },
    name: { type: :string },
    description: { type: :string, nullable: true, description: 'Plain-text description' },
    description_html: { type: :string, nullable: true, description: 'Rich-text description as HTML' },
    started_at: { type: :string, format: :datetime },
    ended_at: { type: :string, format: :datetime },
    distance_meters: { type: :integer, nullable: true, description: 'Calculated in the background after save' },
    visited_countries: { type: :array, items: { type: :string } },
    created_at: { type: :string, format: :datetime },
    updated_at: { type: :string, format: :datetime }
  }
  trip_schema = { type: :object, properties: trip_properties, required: %w[id name started_at ended_at] }
  trip_input = {
    type: :object,
    properties: {
      trip: {
        type: :object,
        properties: {
          name: { type: :string },
          started_at: { type: :string, format: :datetime },
          ended_at: { type: :string, format: :datetime },
          description: { type: :string, description: 'Plain text or HTML' }
        }
      }
    }
  }

  path '/api/v1/trips' do
    get 'List trips' do
      tags 'Trips'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :start_at, in: :query, type: :string, format: :datetime, required: false,
                description: 'Only trips ending at or after this time'
      parameter name: :end_at, in: :query, type: :string, format: :datetime, required: false,
                description: 'Only trips starting at or before this time'
      parameter name: :page, in: :query, type: :integer, required: false,
                description: 'Page number; omit to return all trips'
      parameter name: :per_page, in: :query, type: :integer, required: false,
                description: 'Trips per page (default 25, max 100)'

      response '200', 'trips found' do
        let(:Authorization) { "Bearer #{api_key}" }
        before { create(:trip, user: user) }

        schema type: :array, items: trip_schema

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        run_test!
      end
    end

    post 'Create trip' do
      tags 'Trips'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :trip, in: :body,
                schema: trip_input.deep_merge(properties: { trip: { required: %w[name started_at ended_at] } })

      response '201', 'trip created' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:trip) do
          { trip: { name: 'Weekend', started_at: '2025-05-03T08:00:00Z', ended_at: '2025-05-04T20:00:00Z' } }
        end

        schema trip_schema

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:trip) { { trip: { name: 'No dates' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:trip) { { trip: { name: 'Weekend' } } }

        run_test!
      end
    end
  end

  path '/api/v1/trips/{id}' do
    get 'Show trip' do
      tags 'Trips'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Trip ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '200', 'trip found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { create(:trip, user: user).id }

        schema trip_schema.deep_merge(
          properties: {
            path: {
              type: :array,
              description: 'Route as [longitude, latitude] pairs',
              items: { type: :array, items: { type: :number } }
            }
          }
        )

        run_test!
      end

      response '404', 'trip not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { create(:trip, user: user).id }

        run_test!
      end
    end

    patch 'Update trip' do
      tags 'Trips'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Trip ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :trip, in: :body, schema: trip_input

      response '200', 'trip updated' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { create(:trip, user: user).id }
        let(:trip) { { trip: { name: 'Renamed trip' } } }

        schema trip_schema

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { create(:trip, user: user).id }
        let(:trip) { { trip: { name: '' } } }

        run_test!
      end

      response '404', 'trip not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }
        let(:trip) { { trip: { name: 'Renamed trip' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { create(:trip, user: user).id }
        let(:trip) { { trip: { name: 'Renamed trip' } } }

        run_test!
      end
    end

    delete 'Delete trip' do
      tags 'Trips'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Trip ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '200', 'trip deleted' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { create(:trip, user: user).id }

        run_test!
      end

      response '404', 'trip not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:id) { create(:trip, user: user).id }

        run_test!
      end
    end
  end
end

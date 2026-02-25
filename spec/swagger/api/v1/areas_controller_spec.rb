# frozen_string_literal: true

require 'swagger_helper'

describe 'Areas API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/areas' do
    post 'Creates an area' do
      tags 'Areas'
      description 'Creates a new geographic area for the authenticated user'
      consumes 'application/json'
      produces 'application/json'
      request_body_example value: {
        area: { name: 'Home', latitude: 40.7128, longitude: -74.0060, radius: 100 }
      }
      parameter name: :area, in: :body, schema: {
        type: :object,
        properties: {
          area: {
            type: :object,
            properties: {
              name: { type: :string, example: 'Home', description: 'The name of the area' },
              latitude: { type: :number, example: 40.7128, description: 'The latitude of the area center' },
              longitude: { type: :number, example: -74.0060, description: 'The longitude of the area center' },
              radius: { type: :number, example: 100, description: 'The radius of the area in meters' }
            },
            required: %w[name latitude longitude radius]
          }
        }
      }
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '201', 'area created' do
        schema type: :object,
               properties: {
                 id: { type: :integer, description: 'The ID of the area' },
                 name: { type: :string, description: 'The name of the area' },
                 latitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The latitude of the area center' },
                 longitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The longitude of the area center' },
                 radius: { type: :integer, description: 'The radius of the area in meters' },
                 user_id: { type: :integer, description: 'The ID of the owning user' },
                 created_at: { type: :string, format: 'date-time' },
                 updated_at: { type: :string, format: 'date-time' }
               }

        let(:area) { { area: { name: 'Home', latitude: 40.7128, longitude: -74.0060, radius: 100 } } }

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

      response '422', 'invalid request' do
        let(:area) { { area: { name: 'Home', latitude: 40.7128, longitude: -74.0060 } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:area) { { area: { name: 'Home', latitude: 40.7128, longitude: -74.0060, radius: 100 } } }

        run_test!
      end
    end

    get 'Retrieves all areas' do
      tags 'Areas'
      description 'Returns all areas belonging to the authenticated user'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'areas found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer, example: 1, description: 'The ID of the area' },
                   name: { type: :string, example: 'Home', description: 'The name of the area' },
                   latitude: { oneOf: [{ type: :number }, { type: :string }], example: 40.7128, description: 'The latitude of the area center' },
                   longitude: { oneOf: [{ type: :number }, { type: :string }], example: -74.0060, description: 'The longitude of the area center' },
                   radius: { type: :integer, example: 100, description: 'The radius of the area in meters' }
                 },
                 required: %w[id name latitude longitude radius]
               }

        let!(:areas) { create_list(:area, 3, user:) }

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

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/areas/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true, description: 'Area ID'

    get 'Retrieves a specific area' do
      tags 'Areas'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'area found' do
        schema type: :object,
               properties: {
                 id: { type: :integer, description: 'The ID of the area' },
                 name: { type: :string, description: 'The name of the area' },
                 latitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The latitude of the area center' },
                 longitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The longitude of the area center' },
                 radius: { type: :integer, description: 'The radius of the area in meters' }
               }

        let(:area) { create(:area, user:) }
        let(:id) { area.id }

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

      response '404', 'area not found' do
        let(:id) { 999999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:area).id }

        run_test!
      end
    end

    patch 'Updates an area' do
      tags 'Areas'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :area, in: :body, schema: {
        type: :object,
        properties: {
          area: {
            type: :object,
            properties: {
              name: { type: :string, description: 'The name of the area' },
              latitude: { type: :number, description: 'The latitude of the area center' },
              longitude: { type: :number, description: 'The longitude of the area center' },
              radius: { type: :number, description: 'The radius of the area in meters' }
            }
          }
        }
      }

      response '200', 'area updated' do
        schema type: :object,
               properties: {
                 id: { type: :integer, description: 'The ID of the area' },
                 name: { type: :string, description: 'The name of the area' },
                 latitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The latitude of the area center' },
                 longitude: { oneOf: [{ type: :number }, { type: :string }], description: 'The longitude of the area center' },
                 radius: { type: :integer, description: 'The radius of the area in meters' }
               }

        let(:existing_area) { create(:area, user:) }
        let(:id) { existing_area.id }
        let(:area) { { area: { name: 'Updated Name' } } }

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

      response '404', 'area not found' do
        let(:id) { 999999 }
        let(:area) { { area: { name: 'Updated' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:area).id }
        let(:area) { { area: { name: 'Updated' } } }

        run_test!
      end
    end

    delete 'Deletes an area' do
      tags 'Areas'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'area deleted' do
        let(:area) { create(:area, user:) }
        let(:id) { area.id }

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

      response '404', 'area not found' do
        let(:id) { 999999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:area).id }

        run_test!
      end
    end
  end
end

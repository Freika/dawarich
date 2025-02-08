# frozen_string_literal: true

require 'swagger_helper'

describe 'Areas API', type: :request do
  path '/api/v1/areas' do
    post 'Creates an area' do
      request_body_example value: {
        'name': 'Home',
        'latitude': 40.7128,
        'longitude': -74.0060,
        'radius': 100
      }
      tags 'Areas'
      consumes 'application/json'
      parameter name: :area, in: :body, schema: {
        type: :object,
        properties: {
          name: {
            type: :string,
            example: 'Home',
            description: 'The name of the area'
          },
          latitude: {
            type: :number,
            example: 40.7128,
            description: 'The latitude of the area'
          },
          longitude: {
            type: :number,
            example: -74.0060,
            description: 'The longitude of the area'
          },
          radius: {
            type: :number,
            example: 100,
            description: 'The radius of the area in meters'
          }
        },
        required: %w[name latitude longitude radius]
      }
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '201', 'area created' do
        let(:area)    { { name: 'Home', latitude: 40.7128, longitude: -74.0060, radius: 100 } }
        let(:api_key) { create(:user).api_key }

        run_test!
      end
      response '422', 'invalid request' do
        let(:area)    { { name: 'Home', latitude: 40.7128, longitude: -74.0060 } }
        let(:api_key) { create(:user).api_key }

        run_test!
      end
    end

    get 'Retrieves all areas' do
      tags 'Areas'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'areas found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: {
                     type: :integer,
                     example: 1,
                     description: 'The ID of the area'
                   },
                   name: {
                     type: :string,
                     example: 'Home',
                     description: 'The name of the area'
                   },
                   latitude: {
                     type: :number,
                     example: 40.7128,
                     description: 'The latitude of the area'
                   },
                   longitude: {
                     type: :number,
                     example: -74.0060,
                     description: 'The longitude of the area'
                   },
                   radius: {
                     type: :number,
                     example: 100,
                     description: 'The radius of the area in meters'
                   }
                 },
                 required: %w[id name latitude longitude radius]
               }

        let(:user)    { create(:user) }
        let(:areas)   { create_list(:area, 3, user:) }
        let(:api_key) { user.api_key }

        run_test!
      end
    end
  end

  path '/api/v1/areas/{id}' do
    delete 'Deletes an area' do
      tags 'Areas'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :id, in: :path, type: :string, required: true, description: 'Area ID'

      response '200', 'area deleted' do
        let(:user)    { create(:user) }
        let(:area)    { create(:area, user:) }
        let(:api_key) { user.api_key }
        let(:id)      { area.id }

        run_test!
      end
    end
  end
end

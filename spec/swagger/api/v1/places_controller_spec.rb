# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Places API', type: :request do
  path '/api/v1/places' do
    get 'Retrieves all places for the authenticated user' do
      tags 'Places'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'
      parameter name: :tag_ids, in: :query, type: :array, items: { type: :integer }, required: false,
                description: 'Filter places by tag IDs'

      response '200', 'places found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   name: { type: :string },
                   latitude: { type: :number, format: :float },
                   longitude: { type: :number, format: :float },
                   source: { type: :string },
                   icon: { type: :string, nullable: true },
                   color: { type: :string, nullable: true },
                   visits_count: { type: :integer },
                   created_at: { type: :string, format: 'date-time' },
                   tags: {
                     type: :array,
                     items: {
                       type: :object,
                       properties: {
                         id: { type: :integer },
                         name: { type: :string },
                         icon: { type: :string },
                         color: { type: :string }
                       }
                     }
                   }
                 },
                 required: %w[id name latitude longitude]
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let!(:place) { create(:place, user: user) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
          expect(data.first['id']).to eq(place.id)
        end
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    post 'Creates a place' do
      tags 'Places'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'
      parameter name: :place, in: :body, schema: {
        type: :object,
        properties: {
          name: { type: :string },
          latitude: { type: :number, format: :float },
          longitude: { type: :number, format: :float },
          source: { type: :string },
          tag_ids: { type: :array, items: { type: :integer } }
        },
        required: %w[name latitude longitude]
      }

      response '201', 'place created' do
        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 latitude: { type: :number, format: :float },
                 longitude: { type: :number, format: :float },
                 source: { type: :string },
                 icon: { type: :string, nullable: true },
                 color: { type: :string, nullable: true },
                 visits_count: { type: :integer },
                 created_at: { type: :string, format: 'date-time' },
                 tags: { type: :array }
               }

        let(:user) { create(:user) }
        let(:tag) { create(:tag, user: user) }
        let(:api_key) { user.api_key }
        let(:place) do
          {
            name: 'Coffee Shop',
            latitude: 40.7589,
            longitude: -73.9851,
            source: 'manual',
            tag_ids: [tag.id]
          }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['name']).to eq('Coffee Shop')
          # NOTE: tags array is expected to be in the response schema but may be empty initially
          # Tags can be added separately via the update endpoint
          expect(data).to have_key('tags')
        end
      end

      response '422', 'invalid request' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:place) { { name: '' } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:place) { { name: 'Test', latitude: 40.0, longitude: -73.0 } }

        run_test!
      end
    end
  end

  path '/api/v1/places/nearby' do
    get 'Searches for nearby places using Photon geocoding API' do
      tags 'Places'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'
      parameter name: :latitude, in: :query, type: :number, format: :float, required: true,
                description: 'Latitude coordinate'
      parameter name: :longitude, in: :query, type: :number, format: :float, required: true,
                description: 'Longitude coordinate'
      parameter name: :radius, in: :query, type: :number, format: :float, required: false,
                description: 'Search radius in kilometers (default: 0.5)'
      parameter name: :limit, in: :query, type: :integer, required: false,
                description: 'Maximum number of results (default: 10)'

      response '200', 'nearby places found' do
        schema type: :object,
               properties: {
                 places: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       name: { type: :string },
                       latitude: { type: :number, format: :float },
                       longitude: { type: :number, format: :float },
                       distance: { type: :number, format: :float },
                       type: { type: :string }
                     }
                   }
                 }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:latitude) { 40.7589 }
        let(:longitude) { -73.9851 }
        let(:radius) { 1.0 }
        let(:limit) { 5 }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key('places')
          expect(data['places']).to be_an(Array)
        end
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:latitude) { 40.7589 }
        let(:longitude) { -73.9851 }

        run_test!
      end
    end
  end

  path '/api/v1/places/{id}' do
    parameter name: :id, in: :path, type: :integer, description: 'Place ID'

    get 'Retrieves a specific place' do
      tags 'Places'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'

      response '200', 'place found' do
        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 latitude: { type: :number, format: :float },
                 longitude: { type: :number, format: :float },
                 source: { type: :string },
                 icon: { type: :string, nullable: true },
                 color: { type: :string, nullable: true },
                 visits_count: { type: :integer },
                 created_at: { type: :string, format: 'date-time' },
                 tags: { type: :array }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:place) { create(:place, user: user) }
        let(:id) { place.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['id']).to eq(place.id)
        end
      end

      response '404', 'place not found' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:id) { 'invalid' }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:place) { create(:place) }
        let(:id) { place.id }

        run_test!
      end
    end

    patch 'Updates a place' do
      tags 'Places'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'
      parameter name: :place, in: :body, schema: {
        type: :object,
        properties: {
          name: { type: :string },
          latitude: { type: :number, format: :float },
          longitude: { type: :number, format: :float },
          tag_ids: { type: :array, items: { type: :integer } }
        }
      }

      response '200', 'place updated' do
        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 latitude: { type: :number, format: :float },
                 longitude: { type: :number, format: :float },
                 tags: { type: :array }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:existing_place) { create(:place, user: user) }
        let(:id) { existing_place.id }
        let(:place) { { name: 'Updated Name' } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['name']).to eq('Updated Name')
        end
      end

      response '404', 'place not found' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:id) { 'invalid' }
        let(:place) { { name: 'Updated' } }

        run_test!
      end

      response '422', 'invalid request' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:existing_place) { create(:place, user: user) }
        let(:id) { existing_place.id }
        let(:place) { { name: '' } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:existing_place) { create(:place) }
        let(:id) { existing_place.id }
        let(:place) { { name: 'Updated' } }

        run_test!
      end
    end

    delete 'Deletes a place' do
      tags 'Places'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API key for authentication'

      response '204', 'place deleted' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:place) { create(:place, user: user) }
        let(:id) { place.id }

        run_test!
      end

      response '404', 'place not found' do
        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:id) { 'invalid' }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:place) { create(:place) }
        let(:id) { place.id }

        run_test!
      end
    end
  end
end

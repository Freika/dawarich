# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Locations API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/locations' do
    get 'Searches for location history near coordinates' do
      tags 'Locations'
      description 'Searches for tracked location points near the specified coordinates, optionally filtered by date range'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :lat, in: :query, type: :number, format: :float, required: true,
                description: 'Latitude coordinate to search near'
      parameter name: :lon, in: :query, type: :number, format: :float, required: true,
                description: 'Longitude coordinate to search near'
      parameter name: :limit, in: :query, type: :integer, required: false,
                description: 'Maximum number of results (default: 50)'
      parameter name: :date_from, in: :query, type: :string, required: false,
                description: 'Start date filter (YYYY-MM-DD)'
      parameter name: :date_to, in: :query, type: :string, required: false,
                description: 'End date filter (YYYY-MM-DD)'
      parameter name: :radius_override, in: :query, type: :integer, required: false,
                description: 'Custom search radius in meters'

      response '200', 'locations found' do
        schema type: :object,
               properties: {
                 query: { type: :object, nullable: true, description: 'The search query parameters used' },
                 locations: {
                   type: :array,
                   description: 'Matching location groups',
                   items: {
                     type: :object,
                     properties: {
                       place_name: { type: :string, nullable: true, description: 'Reverse-geocoded place name' },
                       coordinates: { type: :array, items: { type: :number }, description: '[latitude, longitude]' },
                       address: { type: :string, nullable: true, description: 'Full address' },
                       total_visits: { type: :integer, description: 'Total number of visits' },
                       first_visit: { type: :string, nullable: true, description: 'First visit date' },
                       last_visit: { type: :string, nullable: true, description: 'Last visit date' },
                       visits: { type: :array, items: { type: :object }, description: 'Individual visit details' }
                     }
                   }
                 },
                 total_locations: { type: :integer, description: 'Total matching locations' },
                 search_metadata: { type: :object, description: 'Search metadata and statistics' }
               }

        let(:lat) { 52.52 }
        let(:lon) { 13.405 }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '400', 'bad request - missing coordinates' do
        let(:lat) { nil }
        let(:lon) { nil }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:lat) { 52.52 }
        let(:lon) { 13.405 }

        run_test!
      end
    end
  end

  path '/api/v1/locations/suggestions' do
    get 'Get location suggestions from text search' do
      tags 'Locations'
      description 'Returns geocoded location suggestions based on a text search query (min 2 characters)'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :q, in: :query, type: :string, required: true,
                description: 'Search query (minimum 2 characters)'

      response '200', 'suggestions found' do
        schema type: :object,
               properties: {
                 suggestions: {
                   type: :array,
                   description: 'Matching location suggestions',
                   items: {
                     type: :object,
                     properties: {
                       name: { type: :string, description: 'Place name' },
                       address: { type: :string, nullable: true, description: 'Full address' },
                       coordinates: { type: :array, items: { type: :number }, description: '[latitude, longitude]' },
                       type: { type: :string, nullable: true, description: 'Place type (city, street, etc.)' }
                     }
                   }
                 }
               }

        let(:q) { 'Berlin' }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:q) { 'Berlin' }

        run_test!
      end
    end
  end
end

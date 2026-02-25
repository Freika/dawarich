# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Maps Hexagons API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/maps/hexagons' do
    get 'Retrieves hexagon grid data for the map' do
      tags 'Maps'
      description 'Returns hexagonal grid data for map visualization. Supports both authenticated access and public sharing via UUID.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: false,
                description: 'API Key (required for authenticated access, omit when using uuid)'
      parameter name: :uuid, in: :query, type: :string, required: false,
                description: 'Sharing UUID for public access (alternative to api_key)'
      parameter name: :start_date, in: :query, type: :string, required: false,
                description: 'Start date (ISO 8601 format)'
      parameter name: :end_date, in: :query, type: :string, required: false,
                description: 'End date (ISO 8601 format)'
      parameter name: :year, in: :query, type: :integer, required: false, description: 'Year filter'
      parameter name: :month, in: :query, type: :integer, required: false, description: 'Month filter (1-12)'

      response '200', 'hexagons found' do
        schema type: :object,
               properties: {
                 type: { type: :string, example: 'FeatureCollection', description: 'GeoJSON type' },
                 features: {
                   type: :array,
                   description: 'Array of GeoJSON hexagon features',
                   items: {
                     type: :object,
                     properties: {
                       type: { type: :string, example: 'Feature' },
                       geometry: { type: :object, description: 'Hexagon polygon geometry' },
                       properties: { type: :object, description: 'Hexagon properties including point count' }
                     }
                   }
                 },
                 metadata: {
                   type: :object,
                   description: 'Request metadata',
                   properties: {
                     hexagon_count: { type: :integer, description: 'Number of hexagons returned' },
                     total_points: { type: :integer, description: 'Total number of points in all hexagons' },
                     source: { type: :string, description: 'Data source type' }
                   }
                 }
               }

        let(:start_date) { 1.month.ago.iso8601 }
        let(:end_date) { Time.current.iso8601 }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/maps/hexagons/bounds' do
    get 'Retrieves geographic bounds for hexagon data' do
      tags 'Maps'
      description 'Returns the geographic bounding box for the user\'s location data within the specified date range'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: false,
                description: 'API Key (required for authenticated access)'
      parameter name: :uuid, in: :query, type: :string, required: false,
                description: 'Sharing UUID for public access'
      parameter name: :start_date, in: :query, type: :string, required: false,
                description: 'Start date (ISO 8601 format)'
      parameter name: :end_date, in: :query, type: :string, required: false,
                description: 'End date (ISO 8601 format)'

      response '200', 'bounds found' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, description: 'Whether the request was successful' },
                 data: {
                   type: :object,
                   description: 'Bounding box coordinates',
                   properties: {
                     south_west: {
                       type: :object,
                       properties: {
                         lat: { type: :number, description: 'Southwest latitude' },
                         lng: { type: :number, description: 'Southwest longitude' }
                       }
                     },
                     north_east: {
                       type: :object,
                       properties: {
                         lat: { type: :number, description: 'Northeast latitude' },
                         lng: { type: :number, description: 'Northeast longitude' }
                       }
                     }
                   }
                 }
               }

        let(:start_date) { 1.month.ago.iso8601 }
        let(:end_date) { Time.current.iso8601 }

        before do
          create(:point, user: user, latitude: 52.52, longitude: 13.405,
                         lonlat: 'POINT(13.405 52.52)',
                         timestamp: 1.week.ago.to_i)
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

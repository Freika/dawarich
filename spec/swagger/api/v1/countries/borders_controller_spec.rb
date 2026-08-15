# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Countries Borders API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/countries/borders' do
    get 'Retrieves country borders GeoJSON data' do
      tags 'Countries'
      description 'Returns GeoJSON FeatureCollection containing country border geometries. ' \
                  'Response is cached for 1 day.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'borders found' do
        schema type: :object,
               properties: {
                 type: { type: :string, example: 'FeatureCollection', description: 'GeoJSON type' },
                 features: {
                   type: :array,
                   description: 'Array of GeoJSON Feature objects with country borders',
                   items: {
                     type: :object,
                     properties: {
                       type: { type: :string, example: 'Feature' },
                       properties: {
                         type: :object,
                         properties: {
                           name: { type: :string, description: 'Country name' },
                           iso_a3: { type: :string, description: 'ISO 3166-1 alpha-3 country code' }
                         }
                       },
                       geometry: {
                         type: :object,
                         description: 'GeoJSON geometry (Polygon or MultiPolygon)'
                       }
                     }
                   }
                 }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

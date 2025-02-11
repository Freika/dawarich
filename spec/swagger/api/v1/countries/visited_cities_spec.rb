# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Countries::VisitedCities', type: :request do
  path '/api/v1/countries/visited_cities' do
    get 'Get visited cities by date range' do
      tags 'Countries'
      description 'Returns a list of visited cities and countries based on tracked points within the specified date range'
      produces 'application/json'

      parameter name: :api_key,
                in: :query,
                type: :string,
                required: true,
                example: 'a1b2c3d4e5f6g7h8i9j0',
                description: 'Your API authentication key'
      parameter name: :start_at,
                in: :query,
                type: :string,
                format: 'date-time',
                required: true,
                description: 'Start date in YYYY-MM-DD format',
                example: '2023-01-01'

      parameter name: :end_at,
                in: :query,
                type: :string,
                format: 'date-time',
                required: true,
                description: 'End date in YYYY-MM-DD format',
                example: '2023-12-31'

      response '200', 'cities found' do
        schema type: :object,
               properties: {
                 data: {
                   type: :array,
                   description: 'Array of countries and their visited cities',
                   example: [
                     {
                       country: 'Germany',
                       cities: [
                         {
                           city: 'Berlin',
                           points: 4394,
                           timestamp: 1_724_868_369,
                           stayed_for: 24_490
                         },
                         {
                           city: 'Munich',
                           points: 2156,
                           timestamp: 1_724_782_369,
                           stayed_for: 12_450
                         }
                       ]
                     },
                     {
                       country: 'France',
                       cities: [
                         {
                           city: 'Paris',
                           points: 3267,
                           timestamp: 1_724_695_969,
                           stayed_for: 18_720
                         }
                       ]
                     }
                   ],
                   items: {
                     type: :object,
                     properties: {
                       country: {
                         type: :string,
                         example: 'Germany'
                       },
                       cities: {
                         type: :array,
                         items: {
                           type: :object,
                           properties: {
                             city: {
                               type: :string,
                               example: 'Berlin'
                             },
                             points: {
                               type: :integer,
                               example: 4394,
                               description: 'Number of points in the city'
                             },
                             timestamp: {
                               type: :integer,
                               example: 1_724_868_369,
                               description: 'Timestamp of the last point in the city in seconds since Unix epoch'
                             },
                             stayed_for: {
                               type: :integer,
                               example: 24_490,
                               description: 'Number of minutes the user stayed in the city'
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }

        let(:start_at) { '2023-01-01' }
        let(:end_at) { '2023-12-31' }
        let(:api_key) { create(:user).api_key }
        run_test!
      end

      response '400', 'bad request - missing parameters' do
        schema type: :object,
               properties: {
                 error: {
                   type: :string,
                   example: 'Missing required parameters: start_at, end_at'
                 }
               }

        let(:start_at) { nil }
        let(:end_at) { nil }
        let(:api_key) { create(:user).api_key }
        run_test!
      end
    end
  end
end

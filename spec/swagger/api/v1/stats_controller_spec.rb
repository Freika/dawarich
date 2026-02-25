# frozen_string_literal: true

require 'swagger_helper'

describe 'Stats API', type: :request do
  path '/api/v1/stats' do
    get 'Retrieves all stats' do
      tags 'Stats'
      description 'Returns aggregated statistics including total distance, points tracked, countries and cities visited, with yearly breakdowns'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'stats found' do
        schema type: :object,
               properties: {
                 totalDistanceKm: { type: :number, description: 'Total distance traveled in kilometers' },
                 totalPointsTracked: { type: :number, description: 'Total number of location points tracked' },
                 totalReverseGeocodedPoints: { type: :number, description: 'Total points with reverse geocoding data' },
                 totalCountriesVisited: { type: :number, description: 'Total unique countries visited' },
                 totalCitiesVisited: { type: :number, description: 'Total unique cities visited' },
                 yearlyStats: {
                   type: :array,
                   description: 'Statistics broken down by year',
                   items: {
                     type: :object,
                     properties: {
                       year: { type: :integer, description: 'The year' },
                       totalDistanceKm: { type: :number, description: 'Distance traveled in km for this year' },
                       totalCountriesVisited: { type: :number, description: 'Countries visited this year' },
                       totalCitiesVisited: { type: :number, description: 'Cities visited this year' },
                       monthlyDistanceKm: {
                         type: :object,
                         description: 'Distance traveled per month in km',
                         properties: {
                           january: { type: :number },
                           february: { type: :number },
                           march: { type: :number },
                           april: { type: :number },
                           may: { type: :number },
                           june: { type: :number },
                           july: { type: :number },
                           august: { type: :number },
                           september: { type: :number },
                           october: { type: :number },
                           november: { type: :number },
                           december: { type: :number }
                         }
                       }
                     },
                     required: %w[
                       year totalDistanceKm totalCountriesVisited totalCitiesVisited monthlyDistanceKm
                     ]
                   }
                 }
               },
               required: %w[
                 totalDistanceKm totalPointsTracked totalReverseGeocodedPoints totalCountriesVisited
                 totalCitiesVisited yearlyStats
               ]

        let!(:user) { create(:user) }
        let!(:stats_in_2020) { (1..12).map { |month| create(:stat, year: 2020, month:, user:) } }
        let!(:stats_in_2021) { (1..12).map { |month| create(:stat, year: 2021, month:, user:) } }
        let!(:points_in_2020) do
          (1..85).map do |i|
            create(:point, :with_geodata, :reverse_geocoded, timestamp: Time.zone.local(2020, 1, 1).to_i + i.hours,
                                                             user:)
          end
        end
        let!(:points_in_2021) do
          (1..95).map do |i|
            create(:point, :with_geodata, :reverse_geocoded, timestamp: Time.zone.local(2021, 1, 1).to_i + i.hours,
                                                             user:)
          end
        end
        let(:api_key) { user.api_key }

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
end

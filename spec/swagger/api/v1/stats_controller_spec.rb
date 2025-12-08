# frozen_string_literal: true

require 'swagger_helper'

describe 'Stats API', type: :request do
  path '/api/v1/stats' do
    get 'Retrieves all stats' do
      tags 'Stats'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'stats found' do
        schema type: :object,
               properties: {
                 totalDistanceKm:             { type: :number },
                totalPointsTracked:           { type: :number },
                totalReverseGeocodedPoints:   { type: :number },
                totalCountriesVisited:        { type: :number },
                totalCitiesVisited:           { type: :number },
                yearlyStats: {
                  type: :array,
                  items: {
                    type: :object,
                    properties: {
                      year:                   { type: :integer },
                      totalDistanceKm:        { type: :number },
                      totalCountriesVisited:  { type: :number },
                      totalCitiesVisited:     { type: :number },
                      monthlyDistanceKm: {
                        type: :object,
                        properties: {
                          january:    { type: :number },
                          february:   { type: :number },
                          march:      { type: :number },
                          april:      { type: :number },
                          may:        { type: :number },
                          june:       { type: :number },
                          july:       { type: :number },
                          august:     { type: :number },
                          september:  { type: :number },
                          october:    { type: :number },
                          november:   { type: :number },
                          december:   { type: :number }
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

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Digests API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/digests' do
    get 'Lists all yearly digests' do
      tags 'Digests'
      description 'Returns all yearly digests for the authenticated user and available years for generation'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'digests found' do
        schema type: :object,
               properties: {
                 digests: {
                   type: :array,
                   description: 'List of yearly digests',
                   items: {
                     type: :object,
                     properties: {
                       year: { type: :integer, description: 'The year of the digest' },
                       distance: { type: :integer, description: 'Total distance in meters' },
                       countriesCount: { type: :integer, description: 'Number of countries visited' },
                       citiesCount: { type: :integer, description: 'Number of cities visited' },
                       createdAt: { type: :string, format: 'date-time', description: 'When the digest was generated' }
                     }
                   }
                 },
                 availableYears: {
                   type: :array,
                   items: { type: :integer },
                   description: 'Years available for digest generation (no existing digest yet)'
                 }
               }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    post 'Generates a yearly digest' do
      tags 'Digests'
      description 'Queues generation of a yearly digest for the specified year'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :digest_params, in: :body, schema: {
        type: :object,
        properties: {
          year: { type: :integer, description: 'Year to generate digest for', example: 2024 }
        },
        required: %w[year]
      }

      response '202', 'digest generation queued' do
        schema type: :object,
               properties: {
                 message: { type: :string, description: 'Confirmation message' }
               }

        let!(:stats) { (1..12).each { |m| create(:stat, year: 2024, month: m, user: user) } }
        let(:digest_params) { { year: 2024 } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'invalid year' do
        let(:digest_params) { { year: Time.current.year } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:digest_params) { { year: 2024 } }

        run_test!
      end
    end
  end

  path '/api/v1/digests/{year}' do
    parameter name: :year, in: :path, type: :integer, required: true, description: 'Year of the digest'

    get 'Retrieves a yearly digest' do
      tags 'Digests'
      description 'Returns detailed digest data for a specific year'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :distance_unit, in: :query, type: :string, required: false,
                description: 'Distance unit: km or mi (defaults to user setting)'

      response '200', 'digest found' do
        schema type: :object,
               properties: {
                 year: { type: :integer, description: 'The year of the digest' },
                 distance: {
                   type: :object,
                   description: 'Distance details',
                   properties: {
                     meters: { type: :integer, description: 'Total distance in meters' },
                     converted: { type: :number, description: 'Distance in the requested unit' },
                     unit: { type: :string, description: 'Distance unit (km or mi)' },
                     comparisonText: { type: :string, description: 'Fun comparison text' }
                   }
                 },
                 toponyms: {
                   type: :object,
                   description: 'Countries and cities visited',
                   properties: {
                     countriesCount: { type: :integer },
                     citiesCount: { type: :integer },
                     countries: {
                       type: :array,
                       items: {
                         type: :object,
                         properties: {
                           country: { type: :string },
                           cities: { type: :array, items: { type: :string } }
                         }
                       }
                     }
                   }
                 },
                 monthlyDistances: { type: :object, description: 'Distance per month (keyed by month name)' },
                 timeSpentByLocation: { type: :object, description: 'Time spent in each location' },
                 firstTimeVisits: { type: :object, description: 'First-time country and city visits' },
                 yearOverYear: {
                   type: :object,
                   nullable: true,
                   description: 'Year-over-year comparison',
                   properties: {
                     distanceChangePercent: { type: :number },
                     countriesChange: { type: :integer },
                     citiesChange: { type: :integer }
                   }
                 },
                 allTimeStats: {
                   type: :object,
                   description: 'All-time cumulative stats',
                   properties: {
                     totalCountries: { type: :integer },
                     totalCities: { type: :integer },
                     totalDistance: { type: :string }
                   }
                 },
                 travelPatterns: {
                   type: :object,
                   description: 'Travel pattern analysis',
                   properties: {
                     timeOfDay: { type: :object },
                     seasonality: { type: :object },
                     activityBreakdown: { type: :object }
                   }
                 },
                 createdAt: { type: :string, format: 'date-time' },
                 updatedAt: { type: :string, format: 'date-time' }
               }

        let!(:digest) do
          Users::Digest.create!(
            user: user,
            year: 2024,
            period_type: :yearly,
            distance: 150_000,
            toponyms: [{ 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }],
            monthly_distances: { '1' => 10_000, '2' => 12_000 },
            time_spent_by_location: { 'countries' => [], 'cities' => [] },
            first_time_visits: { 'countries' => [], 'cities' => [] },
            year_over_year: {},
            all_time_stats: { 'total_countries' => 5, 'total_cities' => 20, 'total_distance' => 500_000 },
            travel_patterns: {}
          )
        end
        let(:year) { 2024 }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '404', 'digest not found' do
        let(:year) { 1999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:year) { 2024 }

        run_test!
      end
    end

    delete 'Deletes a yearly digest' do
      tags 'Digests'
      description 'Deletes the digest for the specified year'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '204', 'digest deleted' do
        let!(:digest) do
          Users::Digest.create!(
            user: user,
            year: 2024,
            period_type: :yearly,
            distance: 150_000
          )
        end
        let(:year) { 2024 }

        run_test!
      end

      response '404', 'digest not found' do
        let(:year) { 1999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:year) { 2024 }

        run_test!
      end
    end
  end
end

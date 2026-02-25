# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Insights API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  before do
    (1..12).each { |month| create(:stat, year: 2024, month: month, user: user) }
  end

  path '/api/v1/insights' do
    get 'Retrieves insights overview for a year' do
      tags 'Insights'
      description 'Returns aggregated insights including totals, activity heatmap, and available years'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :year, in: :query, type: :integer, required: false,
                description: 'Year to get insights for (defaults to most recent year with data)'
      parameter name: :distance_unit, in: :query, type: :string, required: false,
                description: 'Distance unit: km or mi (defaults to user setting)'

      response '200', 'insights found' do
        schema type: :object,
               properties: {
                 year: { type: :integer, description: 'The selected year' },
                 availableYears: {
                   type: :array,
                   items: { type: :integer },
                   description: 'Years with available data'
                 },
                 totals: {
                   type: :object,
                   description: 'Aggregated totals for the year',
                   properties: {
                     totalDistance: { type: :number, description: 'Total distance traveled' },
                     distanceUnit: { type: :string, description: 'Unit of distance (km or mi)' },
                     countriesCount: { type: :integer, description: 'Number of countries visited' },
                     citiesCount: { type: :integer, description: 'Number of cities visited' },
                     countriesList: { type: :array, items: { type: :string }, description: 'List of country names' },
                     daysTraveling: { type: :number, description: 'Number of days with tracked movement' },
                     biggestMonth: { type: :object, nullable: true, description: 'Month with most distance' }
                   }
                 },
                 activityHeatmap: {
                   type: :object,
                   nullable: true,
                   description: 'Activity heatmap data for the year',
                   properties: {
                     dailyData: { type: :object, description: 'Daily activity data keyed by date' },
                     activityLevels: { type: :object, description: 'Activity level thresholds' },
                     maxDistance: { type: :number, description: 'Maximum daily distance' },
                     activeDays: { type: :integer, description: 'Number of active days' },
                     currentStreak: { type: :integer, description: 'Current consecutive active days' },
                     longestStreak: { type: :integer, description: 'Longest consecutive active days' },
                     longestStreakStart: { type: :string, nullable: true, description: 'Start date of longest streak' },
                     longestStreakEnd: { type: :string, nullable: true, description: 'End date of longest streak' }
                   }
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
  end

  path '/api/v1/insights/details' do
    get 'Retrieves detailed insights with comparisons and travel patterns' do
      tags 'Insights'
      description 'Returns year-over-year comparison and travel pattern analysis'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :year, in: :query, type: :integer, required: false, description: 'Year to get details for'
      parameter name: :distance_unit, in: :query, type: :string, required: false,
                description: 'Distance unit: km or mi (defaults to user setting)'

      response '200', 'details found' do
        schema type: :object,
               properties: {
                 year: { type: :integer, description: 'The selected year' },
                 comparison: {
                   type: :object,
                   nullable: true,
                   description: 'Year-over-year comparison (null if no previous year data)',
                   properties: {
                     previousYear: { type: :integer, description: 'The previous year compared against' },
                     distanceChangePercent: { type: :number, description: 'Percentage change in distance' },
                     countriesChange: { type: :integer, description: 'Change in countries visited' },
                     citiesChange: { type: :integer, description: 'Change in cities visited' },
                     daysChange: { type: :number, description: 'Change in days traveling' }
                   }
                 },
                 travelPatterns: {
                   type: :object,
                   description: 'Travel pattern analysis',
                   properties: {
                     timeOfDay: { type: :object, description: 'Distance distribution by time of day' },
                     dayOfWeek: { type: :array, items: { type: :integer },
description: 'Distance by day of week (Mon-Sun)' },
                     seasonality: { type: :object, description: 'Seasonal travel patterns' },
                     activityBreakdown: { type: :object, description: 'Breakdown by transportation mode' },
                     topVisitedLocations: {
                       type: :array,
                       description: 'Top 5 most visited locations',
                       items: {
                         type: :object,
                         properties: {
                           name: { type: :string },
                           visitCount: { type: :integer },
                           totalDuration: { type: :integer }
                         }
                       }
                     }
                   }
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
  end
end

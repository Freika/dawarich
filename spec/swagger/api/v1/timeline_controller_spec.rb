# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Timeline API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/timeline' do
    get 'Retrieves timeline data for a date range' do
      tags 'Timeline'
      description 'Returns day-by-day timeline data including visits, tracks, and photos for the authenticated user. ' \
                  'Maximum date range is 31 days.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string, required: true,
                description: 'Start date (ISO 8601 format, e.g. 2024-01-01)'
      parameter name: :end_at, in: :query, type: :string, required: true,
                description: 'End date (ISO 8601 format, e.g. 2024-01-31)'
      parameter name: :distance_unit, in: :query, type: :string, required: false,
                description: 'Distance unit: km or mi (defaults to user setting)'

      response '200', 'timeline data found' do
        schema type: :object,
               properties: {
                 days: {
                   type: :array,
                   description: 'Array of day objects with timeline data',
                   items: { type: :object }
                 }
               }

        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '400', 'bad request - missing parameters' do
        let(:start_at) { nil }
        let(:end_at) { nil }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        run_test!
      end
    end
  end
end

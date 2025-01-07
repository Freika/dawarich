# frozen_string_literal: true

require 'swagger_helper'

describe 'Points Tracked Months API', type: :request do
  path '/api/v1/points/tracked_months' do
    get 'Returns list of tracked years and months' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      response '200', 'years and months found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   year: { type: :integer, description: 'Year in YYYY format' },
                   months: {
                     type: :array,
                     items: { type: :string, description: 'Three-letter month abbreviation' }
                   }
                 },
                 required: %w[year months]
               },
               example: [{
                 year: 2024,
                 months: %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
               }]

        let(:api_key) { create(:user).api_key }
        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        run_test!
      end
    end
  end
end

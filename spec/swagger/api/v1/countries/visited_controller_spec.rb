# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Visited Countries API', type: :request do
  path '/api/v1/countries/visited' do
    get 'Returns visited countries for a history scope' do
      tags 'Countries'
      description 'Returns unique country metadata only; location points and boundary geometry are not included.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, required: true,
                schema: { oneOf: [{ type: :integer }, { type: :string, format: :'date-time' }] }
      parameter name: :end_at, in: :query, required: true,
                schema: { oneOf: [{ type: :integer }, { type: :string, format: :'date-time' }] }
      parameter name: :import_id, in: :query, required: false, type: :integer,
                description: 'Optional import filter'

      response '200', 'visited countries found' do
        schema type: :object,
               required: %w[countries],
               properties: {
                 countries: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[iso_a3 name],
                     properties: {
                       iso_a3: { type: :string, example: 'DEU' },
                       name: { type: :string, example: 'Germany' }
                     }
                   }
                 }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:start_at) { 900 }
        let(:end_at) { 1_200 }
        let(:import_id) { nil }

        before do
          country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
          create(:point, user:, country:, timestamp: 1_000)
        end

        run_test!
      end

      response '422', 'invalid history scope' do
        let(:api_key) { create(:user).api_key }
        let(:start_at) { 'invalid' }
        let(:end_at) { 1_200 }
        let(:import_id) { nil }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:start_at) { 900 }
        let(:end_at) { 1_200 }
        let(:import_id) { nil }

        run_test!
      end
    end
  end
end

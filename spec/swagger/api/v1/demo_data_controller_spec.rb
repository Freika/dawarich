# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Demo Data API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/demo_data' do
    get 'Checks whether demo data exists' do
      tags 'Demo Data'
      description 'Returns whether the authenticated user has demo data loaded. ' \
                  'Responds 404 on servers without demo-data support, which clients treat as the capability signal.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'demo data status' do
        schema type: :object,
               properties: {
                 exists: { type: :boolean, description: 'Whether a demo import exists for the user' }
               },
               required: ['exists']

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    post 'Loads demo data' do
      tags 'Demo Data'
      description 'Seeds the demo dataset (Berlin + Prague) for the authenticated user. ' \
                  'Returns 200 with status "exists" when demo data is already loaded.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '201', 'demo data created' do
        schema type: :object,
               properties: {
                 status: { type: :string, enum: ['created'], description: 'Result of the import' }
               },
               required: ['status']

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    delete 'Removes demo data' do
      tags 'Demo Data'
      description 'Removes all demo data (points, visits, places, tags, tracks and the demo trip) ' \
                  'for the authenticated user. Real user data is not touched. ' \
                  'Returns status "no_demo_data" when there is nothing to remove.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'demo data removed' do
        schema type: :object,
               properties: {
                 status: { type: :string, enum: %w[destroyed no_demo_data], description: 'Result of the removal' }
               },
               required: ['status']

        let(:user) do
          create(:user).tap { |u| create(:import, user: u, demo: true) }
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

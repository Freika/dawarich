# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Locations API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/families/locations' do
    get 'Retrieves family members\' locations' do
      tags 'Families'
      description 'Returns the last known locations of all family members who have enabled location sharing. ' \
                  'Requires the family feature to be enabled and the user to be part of a family.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'family locations found' do
        schema type: :object,
               properties: {
                 locations: {
                   type: :array,
                   description: 'Array of family member location data',
                   items: { type: :object }
                 },
                 updated_at: { type: :string, format: 'date-time', description: 'When the data was last updated' },
                 sharing_enabled: { type: :boolean, description: 'Whether the current user has sharing enabled' }
               }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '403', 'user not in a family' do
        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

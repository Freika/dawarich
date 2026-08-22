# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Mine API', type: :request do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_key}" }

  path '/api/v1/families/mine' do
    get 'Retrieves the current user\'s family overview' do
      tags 'Families'
      description 'Returns the family, all members with sharing state, the current user\'s sharing settings, ' \
                  'and active location requests. Requires the Family plan (any plan on self-hosted) and ' \
                  'family membership.'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'

      response '200', 'family overview' do
        schema type: :object,
               properties: {
                 family: { type: :object, properties: { name: { type: :string } } },
                 me: { type: :object },
                 members: { type: :array, items: { type: :object } },
                 location_requests: { type: :object }
               }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        run_test!
      end

      response '404', 'user not in a family' do
        run_test!
      end
    end
  end
end

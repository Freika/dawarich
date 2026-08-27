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
                 me: {
                   type: :object,
                   properties: {
                     user_id: { type: :integer },
                     owner: { type: :boolean },
                     sharing: {
                       type: :object,
                       properties: {
                         enabled: { type: :boolean },
                         duration: { type: :string, nullable: true },
                         expires_at: { type: :string, nullable: true },
                         started_at: { type: :string, nullable: true },
                         share_history: { type: :boolean },
                         history_window: { type: :string, nullable: true }
                       }
                     }
                   }
                 },
                 members: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       user_id: { type: :integer },
                       email: { type: :string },
                       email_initial: { type: :string },
                       owner: { type: :boolean },
                       sharing_enabled: { type: :boolean },
                       joined_at: { type: :string }
                     }
                   }
                 },
                 location_requests: {
                   type: :object,
                   properties: {
                     incoming: {
                       type: :array,
                       items: {
                         type: :object,
                         properties: {
                           id: { type: :integer },
                           requester: {
                             type: :object,
                             properties: {
                               user_id: { type: :integer },
                               email: { type: :string }
                             }
                           },
                           suggested_duration: { type: :string, nullable: true },
                           expires_at: { type: :string },
                           created_at: { type: :string }
                         }
                       }
                     },
                     outgoing: {
                       type: :array,
                       items: {
                         type: :object,
                         properties: {
                           id: { type: :integer },
                           target_user_id: { type: :integer },
                           created_at: { type: :string }
                         }
                       }
                     }
                   }
                 }
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

# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Mine API', type: :request do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_key}" }

  path '/api/v1/families/mine' do
    get 'Retrieves the current user\'s family overview' do
      tags 'Families'
      description 'Returns the family, all members with sharing state, the current user\'s sharing settings, ' \
                  'and active location requests. Requires family membership. A member whose entitlement ' \
                  'has lapsed still gets 200, with `lapsed: true` and a reduced payload carrying only the ' \
                  'family name and the user\'s role — `members` and `location_requests` are omitted. ' \
                  'A user who is neither entitled nor in a family gets 403.'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'

      response '200', 'family overview' do
        schema type: :object,
               properties: {
                 lapsed: { type: :boolean },
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
        before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

        run_test!
      end

      response '403', 'user is neither entitled nor in a family' do
        before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

        run_test!
      end
    end
  end
end

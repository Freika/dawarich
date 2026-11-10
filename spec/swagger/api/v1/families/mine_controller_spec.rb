# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Mine API', type: :request do
  def self.family_error_schema
    {
      type: :object,
      properties: { error: { type: :string }, message: { type: :string } },
      required: %w[error message]
    }
  end

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

    post 'Creates a family with the current user as owner' do
      tags 'Families'
      description 'Creates a family. The caller must be entitled to the family feature and in no family. ' \
                  'Answers with the same body as GET. Refusals carry `error` (a code) and `message` ' \
                  '(English): `feature_disabled` and `family_plan_required` (403, the latter with ' \
                  '`upgrade_url`), `already_in_family`, `family_already_created`, `invalid_name` (422).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string, maxLength: 50 } },
        required: %w[name]
      }

      response '201', 'family created' do
        let(:body) { { name: 'The Testers' } }

        run_test! do |response|
          expect(JSON.parse(response.body)['me']['owner']).to be true
        end
      end

      response '422', 'invalid name' do
        schema family_error_schema
        let(:body) { { name: '' } }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('invalid_name')
        end
      end
    end

    patch 'Renames the current user\'s family' do
      tags 'Families'
      description 'Renames the family. Owner only. Answers with the same body as GET. Refusals: ' \
                  '`owner_required` (403), `invalid_name` (422); a caller in no family gets 404.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string, maxLength: 50 } },
        required: %w[name]
      }

      let(:family) { create(:family, creator: user) }
      let(:body) { { name: 'Renamed' } }

      before { create(:family_membership, :owner, family: family, user: user) }

      response '200', 'family renamed' do
        run_test! do |response|
          expect(JSON.parse(response.body)['family']['name']).to eq('Renamed')
        end
      end

      response '403', 'caller is not the owner' do
        schema family_error_schema
        let(:member) { create(:user) }
        let(:Authorization) { "Bearer #{member.api_key}" }

        before { create(:family_membership, family: family, user: member, role: :member) }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('owner_required')
        end
      end
    end

    delete 'Deletes the current user\'s family' do
      tags 'Families'
      description 'Deletes the family. Owner only, and only when the owner is its last member. ' \
                  'Reachable while the family plan has lapsed. Refusals: `owner_required` (403), ' \
                  '`family_has_members` (422); a caller in no family gets 404.'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'

      let(:family) { create(:family, creator: user) }

      before { create(:family_membership, :owner, family: family, user: user) }

      response '204', 'family deleted' do
        run_test!
      end

      response '422', 'other members are still in the family' do
        schema family_error_schema

        before { create(:family_membership, family: family, user: create(:user), role: :member) }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('family_has_members')
        end
      end
    end
  end
end

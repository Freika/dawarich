# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Members API', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:family) { create(:family, creator: owner) }

  before do
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member, role: :member)
  end

  path '/api/v1/families/members/{user_id}' do
    delete 'Leaves the family, or removes a member from it' do
      tags 'Families'
      description 'With the caller\'s own id, the caller leaves the family. With another member\'s id, the ' \
                  'owner removes that member. Reachable while the family plan has lapsed. Refusals carry ' \
                  '`error` (a code) and `message` (English): `owner_required` (403), `member_not_found` ' \
                  '(404, also for a user of another family), `owner_cannot_leave` (422); a caller in no ' \
                  'family gets `not_in_family` (404).'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :user_id, in: :path, type: :integer, required: true

      response '204', 'member left or was removed' do
        let(:Authorization) { "Bearer #{owner.api_key}" }
        let(:user_id) { member.id }

        run_test!
      end

      response '403', 'caller is not the owner' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } },
               required: %w[error message]
        let(:Authorization) { "Bearer #{member.api_key}" }
        let(:user_id) { owner.id }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('owner_required')
        end
      end

      response '422', 'the owner cannot leave' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } },
               required: %w[error message]
        let(:Authorization) { "Bearer #{owner.api_key}" }
        let(:user_id) { owner.id }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('owner_cannot_leave')
        end
      end
    end
  end
end

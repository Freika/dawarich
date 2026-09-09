# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Location Requests API', type: :request do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_key}" }

  path '/api/v1/families/location_requests' do
    post 'Creates a location sharing request for a family member' do
      tags 'Families'
      description 'Sends a request asking a family member to share their location. Requires the Family plan ' \
                  '(any plan on self-hosted) and family membership.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          target_user_id: { type: :integer, description: 'ID of the family member to request location from' }
        },
        required: ['target_user_id']
      }

      response '201', 'location request created' do
        schema type: :object,
               properties: {
                 request: {
                   type: :object,
                   properties: {
                     id: { type: :integer },
                     target_user_id: { type: :integer },
                     expires_at: { type: :string }
                   }
                 }
               }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:target) { create(:user) }
        let!(:target_membership) { create(:family_membership, family: family, user: target) }
        let(:body) { { target_user_id: target.id } }

        run_test!
      end

      response '404', 'target not found in your family' do
        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:body) { { target_user_id: 0 } }

        run_test!
      end

      response '422', 'target already sharing their location' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:target) { create(:user) }
        let!(:target_membership) { create(:family_membership, family: family, user: target) }
        let(:body) { { target_user_id: target.id } }

        before { target.update_family_location_sharing!(true, duration: 'permanent') }

        run_test!
      end

      response '429', 'request cooldown active' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:target) { create(:user) }
        let!(:target_membership) { create(:family_membership, family: family, user: target) }
        let(:body) { { target_user_id: target.id } }

        before { create(:family_location_request, requester: user, target_user: target, family: family) }

        run_test!
      end
    end
  end

  path '/api/v1/families/location_requests/{id}/accept' do
    parameter name: :id, in: :path, type: :integer, description: 'Location request ID'

    post 'Accepts a location sharing request' do
      tags 'Families'
      description 'Accepts a pending location request and enables sharing for the responder. Requires the ' \
                  'Family plan (any plan on self-hosted) and family membership.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          duration: { type: :string, enum: %w[1h 6h 12h 24h permanent], description: 'How long sharing stays on' }
        }
      }

      response '200', 'request accepted' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 status: { type: :string }
               }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, family: family, user: user) }
        let(:requester) { create(:user) }
        let!(:requester_membership) { create(:family_membership, :owner, family: family, user: requester) }
        let(:request_record) do
          create(:family_location_request, requester: requester, target_user: user, family: family)
        end
        let(:id) { request_record.id }
        let(:body) { { duration: '1h' } }

        run_test!
      end

      response '403', 'not authorized to respond to this request' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:target) { create(:user) }
        let!(:target_membership) { create(:family_membership, family: family, user: target) }
        let(:request_record) do
          create(:family_location_request, requester: user, target_user: target, family: family)
        end
        let(:id) { request_record.id }
        let(:body) { {} }

        run_test!
      end

      response '404', 'location request not found' do
        schema type: :object, properties: { error: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:id) { 0 }
        let(:body) { {} }

        run_test!
      end

      response '422', 'request expired or already responded to' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, family: family, user: user) }
        let(:requester) { create(:user) }
        let!(:requester_membership) { create(:family_membership, :owner, family: family, user: requester) }
        let(:request_record) do
          create(:family_location_request, requester: requester, target_user: user, family: family,
                                           expires_at: 1.hour.ago)
        end
        let(:id) { request_record.id }
        let(:body) { {} }

        run_test!
      end
    end
  end

  path '/api/v1/families/location_requests/{id}/decline' do
    parameter name: :id, in: :path, type: :integer, description: 'Location request ID'

    post 'Declines a location sharing request' do
      tags 'Families'
      description 'Declines a pending location request. Requires the Family plan (any plan on self-hosted) and ' \
                  'family membership.'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'

      response '200', 'request declined' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 status: { type: :string }
               }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, family: family, user: user) }
        let(:requester) { create(:user) }
        let!(:requester_membership) { create(:family_membership, :owner, family: family, user: requester) }
        let(:request_record) do
          create(:family_location_request, requester: requester, target_user: user, family: family)
        end
        let(:id) { request_record.id }

        run_test!
      end

      response '403', 'not authorized to respond to this request' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:target) { create(:user) }
        let!(:target_membership) { create(:family_membership, family: family, user: target) }
        let(:request_record) do
          create(:family_location_request, requester: user, target_user: target, family: family)
        end
        let(:id) { request_record.id }

        run_test!
      end

      response '404', 'location request not found' do
        schema type: :object, properties: { error: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, :owner, family: family, user: user) }
        let(:id) { 0 }

        run_test!
      end

      response '422', 'request expired or already responded to' do
        schema type: :object, properties: { message: { type: :string } }

        let(:family) { create(:family, creator: user) }
        let!(:membership) { create(:family_membership, family: family, user: user) }
        let(:requester) { create(:user) }
        let!(:requester_membership) { create(:family_membership, :owner, family: family, user: requester) }
        let(:request_record) do
          create(:family_location_request, requester: requester, target_user: user, family: family,
                                           status: :accepted, responded_at: Time.current)
        end
        let(:id) { request_record.id }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Invitations API', type: :request do
  def self.family_error_schema
    {
      type: :object,
      properties: { error: { type: :string }, message: { type: :string } },
      required: %w[error message]
    }
  end

  def self.invitation_schema
    {
      type: :object,
      properties: {
        id: { type: :integer },
        email: { type: :string },
        created_at: { type: :string, format: 'date-time' },
        expires_at: { type: :string, format: 'date-time' },
        url: { type: :string, description: 'Public invitation page, built from the request host' }
      },
      required: %w[id email created_at expires_at url]
    }
  end

  def self.token_body
    {
      type: :object,
      properties: { token: { type: :string } },
      required: %w[token]
    }
  end

  let(:owner) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let(:Authorization) { "Bearer #{owner.api_key}" }

  before { create(:family_membership, :owner, family: family, user: owner) }

  path '/api/v1/families/invitations' do
    post 'Invites someone to the current user\'s family by email' do
      tags 'Families'
      description 'Owner only; the caller must be entitled to the family feature. Sends the invitation email. ' \
                  'Refusals carry `error` (a code) and `message` (English): `owner_required` (403), ' \
                  '`invalid_email`, `family_full`, `user_already_in_family`, `invitation_already_sent` (422), ' \
                  '`rate_limited` (429, on Dawarich Cloud after 10 invitations an hour); a caller in no ' \
                  'family gets `not_in_family` (404).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { email: { type: :string, format: :email } },
        required: %w[email]
      }

      response '201', 'invitation created' do
        schema type: :object, properties: { invitation: invitation_schema }, required: %w[invitation]
        let(:body) { { email: 'invitee@example.com' } }

        run_test! do |response|
          expect(JSON.parse(response.body)['invitation']['email']).to eq('invitee@example.com')
        end
      end

      response '422', 'invitation refused' do
        schema family_error_schema
        let(:body) { { email: 'not-an-email' } }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('invalid_email')
        end
      end
    end
  end

  path '/api/v1/families/invitations/{id}' do
    delete 'Revokes a pending invitation' do
      tags 'Families'
      description 'Owner only. Reachable while the family plan has lapsed. Refusals: `owner_required` (403), ' \
                  '`invitation_not_found` (404, also for another family\'s invitation).'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :id, in: :path, type: :integer, required: true

      response '204', 'invitation revoked' do
        let(:id) { create(:family_invitation, family: family, invited_by: owner).id }

        run_test!
      end

      response '404', 'invitation not found' do
        schema family_error_schema
        let(:id) { create(:family_invitation).id }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('invitation_not_found')
        end
      end
    end
  end

  path '/api/v1/families/invitations/preview' do
    post 'Describes an invitation to the person holding its token' do
      tags 'Families'
      description 'The token travels in the body. Open to callers in no family and in `pending_payment`. ' \
                  'Refusals: `feature_disabled` (403), `invitation_not_found` (404), `invitation_invalid` ' \
                  '(422, expired or no longer pending).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: token_body

      let(:invitee) { create(:user, email: 'invitee@example.com') }
      let(:Authorization) { "Bearer #{invitee.api_key}" }
      let(:invitation) do
        create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
      end

      response '200', 'invitation preview' do
        schema type: :object,
               properties: {
                 invitation: {
                   type: :object,
                   properties: {
                     family_name: { type: :string },
                     invited_by_email: { type: :string },
                     email: { type: :string },
                     expires_at: { type: :string, format: 'date-time' },
                     plan_active: { type: :boolean },
                     email_matches: { type: :boolean }
                   },
                   required: %w[family_name invited_by_email email expires_at plan_active email_matches]
                 }
               },
               required: %w[invitation]
        let(:body) { { token: invitation.token } }

        run_test! do |response|
          expect(JSON.parse(response.body)['invitation']['email_matches']).to be true
        end
      end

      response '404', 'unknown token' do
        schema family_error_schema
        let(:body) { { token: 'unknown' } }

        run_test!
      end
    end
  end

  path '/api/v1/families/invitations/accept' do
    post 'Accepts an invitation and joins its family' do
      tags 'Families'
      description 'The token travels in the body. Answers with the same body as GET /api/v1/families/mine. ' \
                  'Open to callers in `pending_payment`, who become active on joining a Cloud family. ' \
                  'Refusals: `feature_disabled`, `email_mismatch` (403), `invitation_not_found` (404), ' \
                  '`invitation_invalid`, `already_in_family`, `plan_inactive`, `family_full` (422).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: token_body

      let(:invitee) { create(:user, email: 'invitee@example.com') }
      let(:Authorization) { "Bearer #{invitee.api_key}" }
      let(:invitation) do
        create(:family_invitation, family: family, invited_by: owner, email: 'invitee@example.com')
      end
      let(:body) { { token: invitation.token } }

      response '200', 'joined the family' do
        run_test! do |response|
          expect(JSON.parse(response.body)['me']['user_id']).to eq(invitee.id)
        end
      end

      response '403', 'invitation is for another email' do
        schema family_error_schema
        let(:Authorization) { "Bearer #{create(:user).api_key}" }

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('email_mismatch')
        end
      end
    end
  end
end

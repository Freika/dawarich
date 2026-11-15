# frozen_string_literal: true

require 'swagger_helper'

describe 'Auth Apple API', type: :request do
  let(:verifier_double) { instance_double(Auth::VerifyAppleToken) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(Auth::VerifyAppleToken).to receive(:new).and_return(verifier_double)
    allow(verifier_double).to receive(:call).and_return(
      sub: '000123.apple', email: 'apple@example.com', email_verified: 'true'
    )
  end

  path '/api/v1/auth/apple' do
    post 'Sign in with Apple' do
      tags 'Auth'
      description 'Exchanges an Apple `id_token` for a Dawarich API key. Creates a new account on first use ' \
                  '(returns 201) or returns the existing account (returns 200). A client that sends ' \
                  '`X-Dawarich-Client-Capabilities: otp_challenge` gets a `202` with a challenge token for an ' \
                  'account with 2FA, as from `POST /api/v1/auth/login`; it then calls ' \
                  '`POST /api/v1/auth/otp_challenge`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: 'X-Dawarich-Client-Capabilities', in: :header, type: :string, required: false,
                description: 'Comma-separated client capabilities; `otp_challenge` asks for the 2FA challenge'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          id_token: { type: :string, description: 'Apple-issued ID token (JWT)' },
          nonce: { type: :string, description: 'Nonce echoed from the Apple sign-in flow', nullable: true }
        },
        required: %w[id_token]
      }

      response '201', 'new user created' do
        schema type: :object,
               properties: {
                 user_id: { type: :integer },
                 email: { type: :string },
                 api_key: { type: :string },
                 status: { type: :string },
                 plan: { type: :string, nullable: true },
                 subscription_source: { type: :string, nullable: true },
                 active_until: { type: :string, format: 'date-time', nullable: true }
               }

        let(:payload) { { id_token: 'fake_token' } }

        run_test!
      end

      response '202', 'two-factor authentication required' do
        schema type: :object,
               properties: {
                 two_factor_required: { type: :boolean },
                 challenge_token: { type: :string },
                 ttl: { type: :integer, description: 'Seconds the challenge token stays valid' }
               },
               required: %w[two_factor_required challenge_token ttl]

        before do
          allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
          create(:user, email: 'apple@example.com', provider: 'apple', uid: '000123.apple',
                        otp_secret: User.generate_otp_secret, otp_required_for_login: true)
        end

        let(:'X-Dawarich-Client-Capabilities') { 'otp_challenge' }
        let(:payload) { { id_token: 'fake_token' } }

        run_test! do |response|
          expect(response.parsed_body).not_to have_key('api_key')
        end
      end

      response '401', 'apple token verification failed' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } }

        before do
          allow(verifier_double).to receive(:call).and_raise(
            Auth::VerifyAppleToken::InvalidToken, 'invalid signature'
          )
        end

        let(:payload) { { id_token: 'bad_token' } }

        run_test!
      end

      response '429', 'a verification email for this address was already sent within the last hour' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } }
        header 'Retry-After', schema: { type: :string },
                              description: 'Seconds until another verification email can be requested'

        before do
          existing = create(:user, email: 'apple@example.com')
          Auth::FindOrCreateOauthUser.acquire_rate_limit(existing.id)
        end

        let(:payload) { { id_token: 'fake_token' } }

        run_test! do |response|
          expect(response.parsed_body['error']).to eq('verification_rate_limited')
        end
      end

      response '409', 'account deletion is in progress' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } }

        before do
          create(:user, email: 'apple@example.com').mark_as_deleted!
        end

        let(:payload) { { id_token: 'fake_token' } }

        run_test! do |response|
          expect(response.parsed_body['error']).to eq('account_pending_deletion')
        end
      end
    end
  end
end

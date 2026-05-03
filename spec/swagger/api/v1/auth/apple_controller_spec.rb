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
                  '(returns 201) or returns the existing account (returns 200).'
      consumes 'application/json'
      produces 'application/json'
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

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
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
    end
  end
end

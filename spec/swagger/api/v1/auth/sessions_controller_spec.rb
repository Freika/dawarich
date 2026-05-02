# frozen_string_literal: true

require 'swagger_helper'

describe 'Auth Sessions API', type: :request do
  path '/api/v1/auth/login' do
    post 'Logs in a user' do
      tags 'Auth'
      description 'Authenticates a user with email and password. ' \
                  'If the user has 2FA enabled, returns a `202` with a one-time challenge token ' \
                  'that must be exchanged via `/api/v1/auth/otp_challenge`. Otherwise returns the api_key.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :credentials, in: :body, schema: {
        type: :object,
        properties: {
          email: { type: :string, format: :email },
          password: { type: :string, format: :password }
        },
        required: %w[email password]
      }

      response '200', 'authenticated successfully' do
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

        let(:user) { create(:user, password: 'secret123456') }
        let(:credentials) { { email: user.email, password: 'secret123456' } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '202', 'two-factor authentication required' do
        schema type: :object,
               properties: {
                 two_factor_required: { type: :boolean },
                 challenge_token: { type: :string,
description: 'Short-lived token to exchange via /auth/otp_challenge' },
                 ttl: { type: :integer, description: 'Token TTL in seconds' }
               }

        let(:user) do
          u = create(:user, password: 'secret123456')
          u.otp_secret = User.generate_otp_secret
          u.otp_required_for_login = true
          u.save!(validate: false)
          u
        end
        let(:credentials) { { email: user.email, password: 'secret123456' } }

        before { allow(DawarichSettings).to receive(:two_factor_available?).and_return(true) }

        run_test!
      end

      response '401', 'invalid credentials' do
        schema type: :object,
               properties: {
                 error: { type: :string },
                 message: { type: :string }
               }

        let(:credentials) { { email: 'unknown@example.com', password: 'wrong' } }

        run_test!
      end
    end
  end
end

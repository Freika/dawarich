# frozen_string_literal: true

require 'swagger_helper'

describe 'Auth OTP Challenges API', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
  end

  let(:user) do
    u = create(:user, password: 'secret123456')
    u.otp_secret = User.generate_otp_secret
    u.otp_required_for_login = true
    u.save!(validate: false)
    u
  end
  let(:challenge_token_value) { Auth::IssueOtpChallengeToken.new(user).call }

  path '/api/v1/auth/otp_challenge' do
    post 'Verifies a two-factor challenge' do
      tags 'Auth'
      description 'Exchanges a challenge_token issued by `/auth/login` plus a current TOTP (or a backup code) ' \
                  'for a full session response with `api_key`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          challenge_token: { type: :string, description: 'Token issued by /auth/login when 2FA is required' },
          otp_code: { type: :string, description: '6-digit TOTP code or one of the user\'s backup codes' }
        },
        required: %w[challenge_token otp_code]
      }

      response '200', 'two-factor verified' do
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

        let(:payload) do
          { challenge_token: challenge_token_value, otp_code: ROTP::TOTP.new(user.otp_secret).now }
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'invalid challenge or otp code' do
        schema type: :object,
               properties: { error: { type: :string }, message: { type: :string } }

        let(:payload) { { challenge_token: challenge_token_value, otp_code: '000000' } }

        run_test!
      end
    end
  end
end

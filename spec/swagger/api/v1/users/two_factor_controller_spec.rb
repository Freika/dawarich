# frozen_string_literal: true

require 'swagger_helper'

describe 'Users Two-Factor API', type: :request do
  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
  end

  let(:user) { create(:user, password: 'secret123456', status: :active) }
  let(:headers_authorization) { "Bearer #{user.api_key}" }

  path '/api/v1/users/me/two_factor/setup' do
    post 'Begins TOTP enrollment' do
      tags 'Users'
      description 'Generates a fresh TOTP secret and provisioning URI. The secret is rotated on each ' \
                  'call until 2FA is confirmed via `/two_factor/confirm`. Requires the user\'s current password.'
      consumes 'application/json'
      produces 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { password: { type: :string, format: :password } },
        required: %w[password]
      }

      response '200', 'secret provisioned' do
        schema type: :object,
               properties: {
                 provisioning_uri: { type: :string, description: 'otpauth:// URI for authenticator apps' },
                 secret: { type: :string, description: 'Base32-encoded TOTP secret' }
               }

        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'secret123456' } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'wrong or missing password' do
        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'wrong' } }

        run_test!
      end

      response '409', 'two-factor already enabled' do
        let(:user) do
          u = create(:user, password: 'secret123456', status: :active)
          u.otp_secret = User.generate_otp_secret
          u.otp_required_for_login = true
          u.save!(validate: false)
          u
        end
        let(:Authorization) { "Bearer #{user.api_key}" }
        let(:payload) { { password: 'secret123456' } }

        run_test!
      end
    end
  end

  path '/api/v1/users/me/two_factor/confirm' do
    post 'Confirms TOTP enrollment' do
      tags 'Users'
      description 'Verifies the supplied TOTP code against the secret provisioned by `/two_factor/setup`. ' \
                  'On success, enables 2FA and returns single-use backup codes.'
      consumes 'application/json'
      produces 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          password: { type: :string, format: :password },
          otp_code: { type: :string, description: 'Current 6-digit TOTP code' }
        },
        required: %w[password otp_code]
      }

      response '200', 'two-factor enabled' do
        schema type: :object,
               properties: {
                 backup_codes: {
                   type: :array,
                   items: { type: :string },
                   description: 'Single-use recovery codes'
                 }
               }

        let(:user) do
          u = create(:user, password: 'secret123456', status: :active)
          u.otp_secret = User.generate_otp_secret
          u.save!(validate: false)
          u
        end
        let(:Authorization) { "Bearer #{user.api_key}" }
        let(:payload) { { password: 'secret123456', otp_code: ROTP::TOTP.new(user.otp_secret).now } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'invalid otp code' do
        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'secret123456', otp_code: '000000' } }

        run_test!
      end
    end
  end

  path '/api/v1/users/me/two_factor/backup_codes' do
    post 'Regenerates two-factor backup codes' do
      tags 'Users'
      description 'Replaces all existing backup codes with a fresh set. Requires the user\'s current password.'
      consumes 'application/json'
      produces 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { password: { type: :string, format: :password } },
        required: %w[password]
      }

      response '200', 'backup codes regenerated' do
        schema type: :object,
               properties: {
                 backup_codes: { type: :array, items: { type: :string } }
               }

        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'secret123456' } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'wrong or missing password' do
        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'wrong' } }

        run_test!
      end
    end
  end

  path '/api/v1/users/me/two_factor' do
    delete 'Disables two-factor authentication' do
      tags 'Users'
      description 'Removes the TOTP secret, clears backup codes, and disables 2FA. Requires either ' \
                  'a current password or a valid OTP code.'
      consumes 'application/json'
      produces 'application/json'
      security [bearer_auth: []]
      parameter name: 'Authorization', in: :header, type: :string, required: true,
                description: 'Bearer token in the format: Bearer {api_key}'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          password: { type: :string, format: :password,
                      description: 'Either password or otp_code is required' },
          otp_code: { type: :string, description: 'Either password or otp_code is required' }
        }
      }

      response '200', 'two-factor disabled' do
        schema type: :object, properties: { message: { type: :string } }

        let(:Authorization) { headers_authorization }
        let(:payload) { { password: 'secret123456' } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'no valid credential supplied' do
        let(:Authorization) { headers_authorization }
        let(:payload) { {} }

        run_test!
      end
    end
  end
end

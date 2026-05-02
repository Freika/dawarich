# frozen_string_literal: true

require 'swagger_helper'

describe 'Auth Registrations API', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  path '/api/v1/auth/register' do
    post 'Registers a new user' do
      tags 'Auth'
      description 'Creates a new user account. On Cloud, the user lands in `pending_payment` ' \
                  'until the subscription service confirms payment. On self-hosted, the user is active immediately.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :credentials, in: :body, schema: {
        type: :object,
        properties: {
          email: { type: :string, format: :email },
          password: { type: :string, format: :password },
          password_confirmation: { type: :string, format: :password }
        },
        required: %w[email password password_confirmation]
      }

      response '201', 'user created' do
        schema type: :object,
               properties: {
                 user_id: { type: :integer, description: 'The new user ID' },
                 email: { type: :string },
                 api_key: { type: :string, description: 'API key used to authenticate subsequent requests' },
                 status: { type: :string, description: 'User status (e.g. pending_payment, active)' },
                 plan: { type: :string, nullable: true },
                 subscription_source: { type: :string, nullable: true },
                 active_until: { type: :string, format: 'date-time', nullable: true }
               }

        let(:credentials) do
          { email: 'new@example.com', password: 'secret123456', password_confirmation: 'secret123456' }
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object,
               properties: {
                 error: { type: :string },
                 details: { type: :object, additionalProperties: true }
               }

        let(:credentials) do
          { email: 'invalid', password: 'short', password_confirmation: 'mismatch' }
        end

        run_test!
      end
    end
  end
end

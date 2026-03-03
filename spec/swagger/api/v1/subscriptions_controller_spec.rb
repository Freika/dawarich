# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Subscriptions API', type: :request do
  path '/api/v1/subscriptions/callback' do
    post 'Processes a subscription callback' do
      tags 'Subscriptions'
      description 'Processes a JWT-encoded subscription callback to update user subscription status. ' \
                  'This endpoint does not require API key authentication — it uses JWT tokens for verification.'
      consumes 'application/json'
      produces 'application/json'
      security [] # Override global security — this endpoint is public
      parameter name: :callback_params, in: :body, schema: {
        type: :object,
        properties: {
          token: { type: :string, description: 'JWT-encoded subscription token' }
        },
        required: %w[token]
      }

      response '200', 'subscription updated' do
        schema type: :object,
               properties: {
                 message: { type: :string, description: 'Confirmation message' }
               }

        let(:user) { create(:user) }
        let(:token) do
          JWT.encode(
            { user_id: user.id, status: 'active', active_until: 1.year.from_now.iso8601 },
            ENV['JWT_SECRET_KEY'],
            'HS256'
          )
        end
        let(:callback_params) { { token: token } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'invalid token' do
        let(:callback_params) { { token: 'invalid_jwt_token' } }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

describe 'Users Exist API', type: :request do
  let(:webhook_secret) { 'test-webhook-secret' }

  before do
    ENV['SUBSCRIPTION_WEBHOOK_SECRET'] = webhook_secret
  end

  after { ENV.delete('SUBSCRIPTION_WEBHOOK_SECRET') }

  path '/api/v1/users/exist' do
    post 'Checks which user IDs exist in Dawarich' do
      tags 'Users'
      description 'Internal endpoint used by the Subscription Manager. Authenticated via the ' \
                  '`X-Webhook-Secret` header (NOT an api_key). Given a list of user IDs, returns ' \
                  'which ones exist and which are missing.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: 'X-Webhook-Secret', in: :header, type: :string, required: true,
                description: 'Shared secret matching SUBSCRIPTION_WEBHOOK_SECRET on the server'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          ids: {
            type: :array,
            items: { type: :integer },
            description: 'User IDs to check for existence'
          }
        },
        required: %w[ids]
      }

      response '200', 'check completed' do
        schema type: :object,
               properties: {
                 existing: { type: :array, items: { type: :integer } },
                 missing: { type: :array, items: { type: :integer } }
               }

        let(:'X-Webhook-Secret') { webhook_secret }
        let(:existing_user) { create(:user) }
        let(:payload) { { ids: [existing_user.id, 999_999_999] } }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'invalid webhook secret' do
        schema type: :object, properties: { error: { type: :string } }

        let(:'X-Webhook-Secret') { 'wrong' }
        let(:payload) { { ids: [1] } }

        run_test!
      end

      response '422', 'ids parameter missing' do
        schema type: :object, properties: { error: { type: :string } }

        let(:'X-Webhook-Secret') { webhook_secret }
        let(:payload) { {} }

        run_test!
      end
    end
  end
end

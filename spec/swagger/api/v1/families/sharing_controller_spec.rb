# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Sharing API', type: :request do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_key}" }

  path '/api/v1/families/sharing' do
    patch 'Updates the current user\'s family location sharing' do
      tags 'Families'
      description 'Enables or disables family location sharing for the current user, with an optional ' \
                  'expiration duration and history-sharing settings. Requires the Family plan (any plan on ' \
                  'self-hosted) and family membership.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer <API Key>'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          enabled: { type: :boolean, description: 'Whether to enable or disable sharing' },
          duration: { type: :string, enum: %w[1h 6h 12h 24h permanent], description: 'How long sharing stays on' },
          share_history: { type: :boolean, description: 'Whether to also share location history' },
          history_window: { type: :string, enum: %w[24h 7d 30d all], description: 'How far back shared history goes' }
        },
        required: ['enabled']
      }

      response '200', 'sharing settings updated' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 enabled: { type: :boolean },
                 duration: { type: :string },
                 message: { type: :string }
               }

        let(:body) { { enabled: true, duration: '24h' } }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        run_test!
      end

      response '400', 'enabled parameter missing' do
        schema type: :object, properties: { error: { type: :string } }

        let(:body) { { share_history: true } }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        run_test!
      end

      response '404', 'user not in a family' do
        let(:body) { { enabled: true } }

        run_test!
      end
    end
  end
end

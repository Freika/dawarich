# frozen_string_literal: true

require 'swagger_helper'

describe 'Plan API', type: :request do
  path '/api/v1/plan' do
    get 'Returns the current user\'s plan and feature flags' do
      tags 'Plan'
      description 'Returns the user\'s plan (`pro` or `lite`), subscription status, and per-feature flags. ' \
                  'On self-hosted, every user is treated as pro and all features return true.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'plan returned' do
        schema type: :object,
               properties: {
                 plan: { type: :string, enum: %w[pro lite] },
                 status: { type: :string },
                 subscription_source: { type: :string, nullable: true },
                 active_until: { type: :string, format: 'date-time', nullable: true },
                 features: {
                   type: :object,
                   properties: {
                     heatmap: { type: :boolean },
                     fog_of_war: { type: :boolean },
                     scratch_map: { type: :boolean },
                     globe_view: { type: :boolean },
                     integrations: { type: :boolean },
                     write_api: {
                       oneOf: [{ type: :boolean }, { type: :string }],
                       description: 'true (Pro), false, or `create_only` for Lite'
                     },
                     sharing: { type: :boolean },
                     full_digest: { type: :boolean },
                     data_window: {
                       type: :string, nullable: true,
                       description: 'null for Pro, `12_months` for Lite'
                     }
                   }
                 }
               }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

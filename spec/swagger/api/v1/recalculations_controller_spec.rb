# frozen_string_literal: true

require 'swagger_helper'

describe 'Recalculations API', type: :request do
  path '/api/v1/recalculations' do
    post 'Queues a full recalculation of the user\'s data' do
      tags 'Recalculations'
      description 'Enqueues `Users::RecalculateDataJob`, which regenerates tracks, stats, visits, ' \
                  'and digests in the background. Optionally scoped to a single year. ' \
                  'A per-user lock prevents concurrent recalculations.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :year, in: :query, type: :integer, required: false,
                description: 'Restrict the recalculation to a single year (2000..current_year+1)'

      response '202', 'recalculation queued' do
        schema type: :object, properties: { message: { type: :string } }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:year) { nil }

        before { Rails.cache.delete("recalculation_pending:#{user.id}") }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '400', 'invalid year' do
        schema type: :object, properties: { error: { type: :string } }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:year) { 1500 }

        run_test!
      end

      response '409', 'recalculation already in progress' do
        schema type: :object, properties: { error: { type: :string } }

        let(:user) { create(:user) }
        let(:api_key) { user.api_key }
        let(:year) { nil }

        before { Rails.cache.write("recalculation_pending:#{user.id}", true, expires_in: 30.minutes) }
        after { Rails.cache.delete("recalculation_pending:#{user.id}") }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:year) { nil }

        run_test!
      end
    end
  end
end

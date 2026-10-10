# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Achievements API', type: :request do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_key}" }
  let(:key) { 'continent_europe' }

  before do
    allow_any_instance_of(Achievements::RegionSilhouettes).to receive(:call).and_return({})
    allow(Achievements::RegionSilhouettes).to receive(:collection).and_return(nil)
  end

  path '/api/v1/achievements' do
    get 'Read lifetime achievement collections' do
      tags 'Achievements'
      produces 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      response '200', 'Lifetime overview; does not claim or celebrate unlocks' do
        schema '$ref' => '#/components/schemas/AchievementOverview'
        run_test!
      end
      response '401', 'Invalid API key' do
        let(:Authorization) { 'Bearer invalid' }
        run_test!
      end
    end
  end

  path '/api/v1/achievements/{key}' do
    parameter name: :key, in: :path, type: :string
    get 'Browse a continent or country collection' do
      tags 'Achievements'
      produces 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :q, in: :query, required: false, schema: { type: :string, maxLength: 100 }
      parameter name: :status, in: :query, required: false,
                schema: { type: :string, enum: %w[all unlocked in_progress locked], default: 'all' }
      parameter name: :page, in: :query, required: false, schema: { type: :integer, minimum: 1, default: 1 }
      response '200', 'Filtered page with visible SVG silhouettes' do
        schema '$ref' => '#/components/schemas/AchievementCollection'
        run_test!
      end
      response '404', 'Unknown or hidden collection' do
        let(:key) { 'missing' }
        run_test!
      end
      response '422', 'Invalid page or filter' do
        let(:page) { -1 }
        run_test!
      end
    end
  end

  path '/api/v1/achievements/{key}/sharing' do
    parameter name: :key, in: :path, type: :string
    patch 'Set sharing explicitly and idempotently' do
      tags 'Achievements'
      consumes 'application/json'
      produces 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :payload, in: :body, schema: {
        type: :object, required: ['enabled'], properties: { enabled: { type: :boolean } }
      }
      let(:payload) { { enabled: true } }
      response '200', 'Updated public sharing state' do
        schema '$ref' => '#/components/schemas/AchievementSharingResult'
        run_test!
      end
      response '422', 'Enabled must be a JSON boolean' do
        let(:payload) { { enabled: 'false' } }
        run_test!
      end
    end
  end

  path '/api/v1/achievements/unlocks/next' do
    post 'Claim or resume the next unlock with a shared web and mobile lease' do
      tags 'Achievements'
      consumes 'application/json'
      produces 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :payload, in: :body, required: false, schema: {
        type: :object, properties: {
          claim_token: { type: :string, pattern: '^[0-9a-f]{32}$' }, batch_end_id: { type: :integer, minimum: 1 }
        }
      }
      let(:payload) { {} }
      response '200', 'Structured collectible card and batch boundary' do
        before do
          create(:achievement_progress, user: user, achievement_key: 'exploration',
                                        state: { 'earned' => { 'FR' => Time.current.iso8601 } })
          Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
        end
        schema '$ref' => '#/components/schemas/AchievementUnlock'
        run_test!
      end
      response '204', 'No pending unlocks' do
        run_test!
      end
      response '409', 'Another client holds the lease; retry after 2 seconds' do
        before do
          Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR')
          Achievements::UnlockDeck.new(user).claim
        end
        schema type: :object, properties: { retry_after: { type: :integer, example: 2 } }
        run_test!
      end
      response '422', 'Invalid token or batch ID' do
        let(:payload) { { batch_end_id: -1 } }
        run_test!
      end
    end
  end

  path '/api/v1/achievements/unlocks/{id}/seen' do
    parameter name: :id, in: :path, schema: { type: :integer, minimum: 1 }
    post 'Acknowledge an unlock for the authenticated account' do
      tags 'Achievements'
      consumes 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :payload, in: :body, schema: {
        type: :object, required: ['claim_token'],
        properties: { claim_token: { type: :string, pattern: '^[0-9a-f]{32}$' } }
      }
      let(:event) { Achievements::UnlockEvent.create!(user: user, kind: 'geography', key: 'FR') }
      let(:claim) { Achievements::UnlockDeck.new(user).claim }
      let(:id) { event.id }
      let(:payload) { { claim_token: claim.event.claim_token } }
      response '204', 'Acknowledged (including repeated acknowledgement)' do
        before { event }
        run_test!
      end
      response '409', 'Wrong token or account' do
        let(:payload) { { claim_token: 'a' * 32 } }
        run_test!
      end
      response '422', 'Invalid ID or missing token' do
        let(:payload) { {} }
        run_test!
      end
    end
  end

  path '/api/v1/achievements/unlocks/dismiss' do
    post 'Dismiss pending unlocks through the batch boundary' do
      tags 'Achievements'
      consumes 'application/json'
      security [{ bearer_auth: [] }, { api_key: [] }]
      parameter name: :Authorization, in: :header, type: :string
      parameter name: :payload, in: :body, schema: {
        type: :object, required: ['batch_end_id'], properties: { batch_end_id: { type: :integer, minimum: 1 } }
      }
      let(:payload) { { batch_end_id: 1 } }
      response '204', 'Batch dismissed; later unlocks remain pending' do
        run_test!
      end
      response '422', 'Invalid batch ID' do
        let(:payload) { { batch_end_id: -1 } }
        run_test!
      end
    end
  end
end

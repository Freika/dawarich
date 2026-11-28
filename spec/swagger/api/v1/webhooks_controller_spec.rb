# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Webhooks API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  webhook_schema = {
    type: :object,
    properties: {
      id: { type: :integer }, name: { type: :string }, url: { type: :string },
      event_types: { type: :array, items: { type: :integer }, description: '0 = enter, 1 = leave' },
      place_ids: { type: :array, items: { type: :integer }, description: 'Empty = every place' },
      active: { type: :boolean }, consecutive_failures: { type: :integer },
      last_delivery_at: { type: :string, format: :'date-time', nullable: true },
      last_success_at: { type: :string, format: :'date-time', nullable: true }
    }
  }

  path '/api/v1/webhooks' do
    get 'Lists geofence webhooks' do
      tags 'Geofencing'
      description 'Webhooks receive signed geofence enter/leave events. Pro or Family plan on Dawarich Cloud.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'webhooks' do
        before { create(:webhook, user:) }

        run_test!
      end

      response '403', 'pro_plan_required: the user is on the Lite plan of Dawarich Cloud' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          user.update!(plan: :lite)
        end

        run_test! do |response|
          expect(JSON.parse(response.body)['error']).to eq('pro_plan_required')
        end
      end
    end

    post 'Creates a geofence webhook' do
      tags 'Geofencing'
      description 'Returns the signing secret once. Requests carry X-Dawarich-Signature: sha256=<HMAC of the body>.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :webhook, in: :body, schema: {
        type: :object,
        properties: {
          webhook: {
            type: :object, required: %w[name url],
            properties: {
              name: { type: :string }, url: { type: :string },
              event_types: { type: :array, items: { type: :integer } },
              place_ids: { type: :array, items: { type: :integer } }, active: { type: :boolean }
            }
          }
        }
      }

      response '201', 'webhook created, secret included' do
        let(:webhook) { { webhook: { name: 'Home Assistant', url: 'https://203.0.113.10/api/webhook/x' } } }

        run_test!
      end

      response '422', 'invalid webhook' do
        let(:webhook) { { webhook: { name: 'x', url: 'ftp://x' } } }

        run_test!
      end
    end
  end

  path '/api/v1/webhooks/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true

    get 'Retrieves a geofence webhook' do
      tags 'Geofencing'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'webhook, without its secret' do
        schema webhook_schema
        let(:id) { create(:webhook, user:).id }

        run_test!
      end

      response '404', 'webhook not found' do
        let(:id) { 0 }

        run_test!
      end
    end

    patch 'Updates a geofence webhook' do
      tags 'Geofencing'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :webhook, in: :body, schema: {
        type: :object,
        properties: {
          webhook: {
            type: :object,
            properties: {
              name: { type: :string }, url: { type: :string },
              event_types: { type: :array, items: { type: :integer } },
              place_ids: { type: :array, items: { type: :integer } }, active: { type: :boolean }
            }
          }
        }
      }

      response '200', 'webhook updated' do
        schema webhook_schema
        let(:id) { create(:webhook, user:).id }
        let(:webhook) { { webhook: { name: 'Node-RED', active: false } } }

        run_test!
      end

      response '422', 'invalid webhook' do
        let(:id) { create(:webhook, user:).id }
        let(:webhook) { { webhook: { url: 'ftp://x' } } }

        run_test!
      end
    end

    delete 'Deletes a geofence webhook' do
      tags 'Geofencing'
      description 'Also allowed on the Lite plan, so webhooks can be removed after a downgrade.'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '204', 'webhook deleted' do
        let(:id) { create(:webhook, user:).id }

        run_test!
      end
    end
  end

  path '/api/v1/webhooks/{id}/regenerate_secret' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Replaces the signing secret of a geofence webhook' do
      tags 'Geofencing'
      description 'The previous secret stops working immediately.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'the new secret' do
        schema type: :object, properties: { secret: { type: :string } }, required: %w[secret]
        let(:id) { create(:webhook, user:).id }

        run_test!
      end
    end
  end

  path '/api/v1/webhooks/{id}/test' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Sends a test event to a webhook' do
      tags 'Geofencing'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '202', 'test delivery queued' do
        let(:id) { create(:webhook, user:).id }

        before { create(:place, :geofence, user:) }

        run_test!
      end

      response '429', 'more than five test sends a minute for this webhook (Dawarich Cloud only)' do
        let(:id) { create(:webhook, user:).id }

        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          user.update!(plan: :pro, active_until: 1.year.from_now)
          create(:place, :geofence, user:)
          5.times { post "/api/v1/webhooks/#{id}/test", params: { api_key: user.api_key } }
        end

        run_test! do |response|
          expect(JSON.parse(response.body)).to eq('error' => 'rate_limited')
        end
      end
    end
  end
end

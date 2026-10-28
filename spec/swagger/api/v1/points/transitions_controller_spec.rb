# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Geofence Transitions API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:place) { create(:place, :geofence, user:) }
  let(:transition) do
    { place_id: place.id, event_type: 'enter', occurred_at: 1.minute.ago.iso8601, lonlat: [13.539, 52.437],
      accuracy_m: 15, device_id: 'phone-1', metadata: { battery: 0.8 } }
  end

  before { GeofenceEvents::StateStore.new(user).reset! }

  path '/api/v1/points/transitions' do
    post 'Reports a geofence enter or leave detected on the device' do
      tags 'Geofencing'
      description 'Records an enter or leave of a notifying place reported by the mobile app ' \
                  'and delivers it to the user\'s webhooks. ' \
                  'Transitions older than 24 hours or more than 5 minutes in the future are rejected.'
      consumes 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :transition, in: :body, schema: {
        type: :object,
        required: %w[place_id event_type occurred_at lonlat],
        properties: {
          place_id: { type: :integer },
          event_type: { type: :string, enum: %w[enter leave] },
          occurred_at: { type: :string, format: :'date-time' },
          lonlat: { type: :array, items: { type: :number }, minItems: 2, maxItems: 2,
                    description: '[longitude, latitude]' },
          accuracy_m: { type: :integer, nullable: true },
          device_id: { type: :string, nullable: true, maxLength: 255 },
          metadata: { type: :object, description: 'Flat object of up to 20 scalar values' }
        }
      }

      response '201', 'transition recorded' do
        run_test!
      end

      response '204', 'place does not belong to the user or does not notify' do
        let(:transition) { super().merge(place_id: create(:place, :geofence).id) }

        run_test!
      end

      response '422', 'invalid transition' do
        let(:transition) { super().merge(event_type: 'linger') }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

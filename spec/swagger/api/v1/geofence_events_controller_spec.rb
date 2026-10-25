# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Geofence Events API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/geofence_events' do
    get 'Lists geofence enter/leave events' do
      tags 'Geofencing'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :place_id, in: :query, type: :integer, required: false
      parameter name: :start_at, in: :query, type: :string, format: :date, required: false,
                description: 'First day, in the user timezone'
      parameter name: :end_at, in: :query, type: :string, format: :date, required: false,
                description: 'Last day, in the user timezone'
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response '200', 'events, newest first' do
        schema type: :array, items: {
          type: :object,
          properties: {
            id: { type: :integer }, place_id: { type: :integer }, place_name: { type: :string },
            event_type: { type: :string, enum: %w[enter leave] },
            source: { type: :string, enum: %w[native_app server_inferred owntracks_native] },
            occurred_at: { type: :string, format: :'date-time' },
            latitude: { type: :number }, longitude: { type: :number }, accuracy_m: { type: :integer, nullable: true }
          }
        }
        before { create(:geofence_event, user:) }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Track Points API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/tracks/{track_id}/points' do
    parameter name: :track_id, in: :path, type: :integer, required: true, description: 'Track ID'

    get 'Retrieves points for a track' do
      tags 'Tracks'
      description 'Returns location points belonging to a specific track, ordered by timestamp ascending'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :page, in: :query, type: :integer, required: false,
                description: 'Page number (optional pagination)'
      parameter name: :per_page, in: :query, type: :integer, required: false, description: 'Items per page (max 1000)'

      response '200', 'points found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer, description: 'Point ID' },
                   latitude: { type: :string, nullable: true, description: 'Latitude coordinate' },
                   longitude: { type: :string, nullable: true, description: 'Longitude coordinate' },
                   timestamp: { type: :number, description: 'Unix timestamp' },
                   velocity: { type: :number, nullable: true, description: 'Velocity in km/h' },
                   country_name: { type: :string, nullable: true, description: 'Country name from reverse geocoding' }
                 }
               }

        let!(:track) { create(:track, user: user) }
        let(:track_id) { track.id }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '404', 'track not found' do
        let(:track_id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:track_id) { create(:track).id }

        run_test!
      end
    end
  end
end

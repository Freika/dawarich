# frozen_string_literal: true

require 'swagger_helper'

describe 'Immich Enrich API', type: :request do
  let(:user) do
    u = create(:user)
    settings = u.settings.merge('immich_url' => 'https://immich.example.com', 'immich_api_key' => 'secret')
    u.update_column(:settings, settings)
    u
  end
  let(:api_key) { user.api_key }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  path '/api/v1/immich/enrich/scan' do
    post 'Scans Immich for photos missing geodata' do
      tags 'Immich'
      description 'Calls the configured Immich instance and returns photos that lack location data ' \
                  'along with candidate points from Dawarich within the configured time tolerance.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_date, in: :query, type: :string, required: false,
                description: 'Earliest photo capture date (ISO 8601)'
      parameter name: :end_date, in: :query, type: :string, required: false,
                description: 'Latest photo capture date (ISO 8601)'
      parameter name: :tolerance, in: :query, type: :integer, required: false,
                description: 'Match tolerance in seconds. Defaults to 1800 (30 min).'

      response '200', 'scan completed' do
        schema type: :object,
               properties: {
                 matches: { type: :array, items: { type: :object } },
                 total_without_geodata: { type: :integer },
                 total_matched: { type: :integer },
                 error: { type: :string, nullable: true }
               }

        before do
          allow_any_instance_of(Immich::EnrichScan).to receive(:call).and_return(
            matches: [], total_without_geodata: 0, total_matched: 0
          )
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/immich/enrich' do
    post 'Writes location data back to Immich photos' do
      tags 'Immich'
      description 'Pushes latitude/longitude updates for the supplied Immich asset IDs back to the user\'s Immich instance.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          assets: {
            type: :array,
            description: 'List of assets to enrich',
            items: {
              type: :object,
              properties: {
                immich_asset_id: { type: :string },
                latitude: { type: :number },
                longitude: { type: :number }
              },
              required: %w[immich_asset_id latitude longitude]
            }
          }
        },
        required: %w[assets]
      }

      response '200', 'enrich completed' do
        schema type: :object, additionalProperties: true

        let(:payload) do
          { assets: [{ immich_asset_id: 'abc-123', latitude: 52.52, longitude: 13.405 }] }
        end

        before do
          allow_any_instance_of(Immich::EnrichPhotos).to receive(:call).and_return(
            updated: 1, failed: 0
          )
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:payload) { { assets: [] } }

        run_test!
      end
    end
  end
end

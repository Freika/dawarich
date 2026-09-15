# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Point Position API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_120),
                   original_path: 'LINESTRING(0 0, 0.02 0)')
  end
  let!(:first_point) { create(:point, user:, track:, timestamp: 1_000, longitude: 0, latitude: 0) }
  let!(:last_point) { create(:point, user:, track:, timestamp: 1_120, longitude: 0.02, latitude: 0) }
  let(:point_id) { first_point.id }
  let(:payload) do
    {
      point: { latitude: 0.01, longitude: 0.01, revision: first_point.lock_version },
      track_revision: track.lock_version,
      history_scope: { start_at: 900, end_at: 1_200 }
    }
  end

  path '/api/v1/points/{point_id}/position' do
    parameter name: :point_id, in: :path, type: :integer, required: true, description: 'Point ID'

    patch 'Moves a point and synchronously recalculates its track' do
      tags 'Points'
      description 'Atomically moves one point and returns the canonical point, track, segments, and revisions.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[point history_scope],
        properties: {
          point: {
            type: :object,
            required: %w[latitude longitude revision],
            properties: {
              latitude: { type: :number, format: :double },
              longitude: { type: :number, format: :double },
              revision: { type: :integer }
            }
          },
          track_revision: { type: :integer, nullable: true },
          history_scope: {
            type: :object,
            required: %w[start_at end_at],
            properties: {
              start_at: { oneOf: [{ type: :integer }, { type: :string, format: :'date-time' }] },
              end_at: { oneOf: [{ type: :integer }, { type: :string, format: :'date-time' }] },
              import_id: { type: :integer, nullable: true }
            }
          }
        }
      }

      response '200', 'point moved and track recalculated' do
        schema type: :object,
               required: %w[point track revision visited_countries],
               properties: {
                 point: { type: :object },
                 track: { type: :object, nullable: true, description: 'Canonical GeoJSON Track feature' },
                 revision: {
                   type: :object,
                   properties: {
                     point: { type: :integer },
                     track: { type: :integer, nullable: true }
                   }
                 },
                 visited_countries: {
                   type: :object,
                   nullable: true,
                   properties: { iso_a3: { type: :array, items: { type: :string } } }
                 }
               }

        run_test!
      end

      response '409', 'stale edit; canonical state returned' do
        let(:payload) do
          super().deep_merge(point: { revision: first_point.lock_version + 1 })
        end

        run_test!
      end

      response '422', 'invalid coordinates, history scope, or recalculation timeout' do
        let(:payload) { super().deep_merge(point: { latitude: 91 }) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

describe 'Map range statistics API', type: :request do
  path '/api/v1/maps/statistics' do
    get 'Returns point count and GPS distance for an exact map period' do
      tags 'Maps'
      produces 'application/json'
      description 'Own non-anomalous points within the plan window, with privacy zones masked. ' \
                  'Inclusive timestamps; offsetless times use the account timezone. ' \
                  'Distance is in meters, split by tracker, recorded track boundaries and the route time threshold. ' \
                  'Family history and manually added flights are excluded.'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string, required: true,
                description: 'ISO 8601 time or Unix seconds'
      parameter name: :end_at, in: :query, type: :string, required: true,
                description: 'ISO 8601 time or Unix seconds'
      parameter name: :import_id, in: :query, type: :integer, required: false

      let(:api_key) { create(:user).api_key }
      let(:start_at) { '2026-07-25T18:15:00Z' }
      let(:end_at) { '2026-07-26T01:00:00Z' }

      response '200', 'statistics' do
        schema type: :object, required: %w[points distance_meters], properties: {
          points: { type: :integer, minimum: 0 },
          distance_meters: { type: :number, minimum: 0 }
        }
        run_test!
      end

      response '400', 'invalid or missing range' do
        let(:start_at) { 'invalid' }
        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        run_test!
      end

      response '503', 'query timeout; retry with a shorter period' do
        before do
          allow_any_instance_of(Maps::RangeStatistics).to receive(:call).and_raise(ActiveRecord::QueryCanceled)
        end
        run_test!
      end
    end
  end
end

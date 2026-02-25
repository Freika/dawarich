# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Tracks API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/tracks' do
    get 'Retrieves tracks as GeoJSON' do
      tags 'Tracks'
      description 'Returns paginated tracks as a GeoJSON FeatureCollection with LineString geometries'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string, required: false,
                description: 'Start date filter (ISO 8601 format)'
      parameter name: :end_at, in: :query, type: :string, required: false,
                description: 'End date filter (ISO 8601 format)'
      parameter name: :page, in: :query, type: :integer, required: false, description: 'Page number'
      parameter name: :per_page, in: :query, type: :integer, required: false, description: 'Items per page'

      response '200', 'tracks found' do
        schema type: :object,
               properties: {
                 type: { type: :string, example: 'FeatureCollection', description: 'GeoJSON type' },
                 features: {
                   type: :array,
                   description: 'Array of GeoJSON Feature objects',
                   items: {
                     type: :object,
                     properties: {
                       type: { type: :string, example: 'Feature' },
                       geometry: {
                         type: :object,
                         properties: {
                           type: { type: :string, example: 'LineString' },
                           coordinates: {
                             type: :array,
                             description: 'Array of [longitude, latitude] coordinate pairs',
                             items: { type: :array, items: { type: :number } }
                           }
                         }
                       },
                       properties: {
                         type: :object,
                         properties: {
                           id: { type: :integer, description: 'Track ID' },
                           color: { type: :string, description: 'Display color for the track' },
                           start_at: { type: :string, description: 'Track start time (ISO 8601)' },
                           end_at: { type: :string, description: 'Track end time (ISO 8601)' },
                           distance: { type: :number, description: 'Distance in meters' },
                           avg_speed: { type: :number, description: 'Average speed in km/h' },
                           duration: { type: :number, description: 'Duration in seconds' },
                           dominant_mode: { type: :string, nullable: true, description: 'Primary transportation mode' },
                           dominant_mode_emoji: { type: :string, nullable: true, description: 'Emoji for transportation mode' }
                         }
                       }
                     }
                   }
                 }
               }

        let!(:track) { create(:track, user: user) }

        after do |example|
          content = example.metadata[:response][:content] || {}
          example.metadata[:response][:content] = content.merge(
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          )
        end

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/tracks/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true, description: 'Track ID'

    get 'Retrieves a single track as GeoJSON' do
      tags 'Tracks'
      description 'Returns a single track as a GeoJSON FeatureCollection, including track segment details'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'track found' do
        schema type: :object,
               properties: {
                 type: { type: :string, example: 'FeatureCollection' },
                 features: { type: :array, items: { type: :object } }
               }

        let!(:track) { create(:track, user: user) }
        let(:id) { track.id }

        after do |example|
          content = example.metadata[:response][:content] || {}
          example.metadata[:response][:content] = content.merge(
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          )
        end

        run_test!
      end

      response '404', 'track not found' do
        let(:id) { 999999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:track).id }

        run_test!
      end
    end
  end
end

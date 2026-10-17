# frozen_string_literal: true

require 'swagger_helper'

describe 'Track Segments API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }
  let(:track) { create(:track, user: user) }
  let!(:segment) { create(:track_segment, :anchored, track: track, transportation_mode: :cycling) }
  let(:track_id) { track.id }

  segment_schema = {
    type: :object,
    properties: {
      id: { type: :integer },
      track_id: { type: :integer },
      transportation_mode: { type: :string, example: 'cycling' },
      start_at: { type: :string, format: :datetime, nullable: true },
      end_at: { type: :string, format: :datetime, nullable: true },
      start_index: { type: :integer, nullable: true },
      end_index: { type: :integer, nullable: true },
      distance: { type: :integer, nullable: true, description: 'Meters' },
      duration: { type: :integer, nullable: true, description: 'Seconds' },
      avg_speed: { type: :number, nullable: true, description: 'km/h' },
      max_speed: { type: :number, nullable: true, description: 'km/h' },
      confidence: { type: :string, nullable: true, enum: [nil, 'low', 'medium', 'high'] },
      confidence_score: { type: :number, nullable: true },
      source: {
        type: :string, nullable: true, example: 'inferred',
        description: 'How the mode was decided. One of inferred, hints+inferred, ' \
                     'device (the tracker stated the mode as certain), user (manual correction), default'
      },
      corrected_at: { type: :string, format: :datetime, nullable: true },
      manually_corrected: { type: :boolean }
    },
    required: %w[id track_id transportation_mode source corrected_at manually_corrected]
  }

  track_segments_properties = {
    track_id: { type: :integer },
    dominant_mode: { type: :string, nullable: true },
    enabled_modes: {
      type: :array, items: { type: :string },
      description: "Transportation modes enabled in the user's settings; the only valid override values"
    },
    segments: { type: :array, items: segment_schema }
  }

  path '/api/v1/tracks/{track_id}/segments' do
    get "Lists a track's transportation-mode segments" do
      tags 'Tracks'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :track_id, in: :path, type: :integer, required: true, description: 'Track ID'

      response '200', 'segments found' do
        let(:Authorization) { "Bearer #{api_key}" }

        schema type: :object, properties: track_segments_properties,
               required: %w[track_id dominant_mode enabled_modes segments]

        run_test!
      end

      response '404', 'track not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:track_id) { create(:track, user: create(:user)).id }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }

        run_test!
      end
    end
  end

  path '/api/v1/tracks/{track_id}/segments/{id}' do
    patch "Corrects a segment's transportation mode or resets it to auto-detection" do
      tags 'Tracks'
      description 'Send `transportation_mode` to override the detected mode, or `reset: true` to drop the ' \
                  'correction and re-run detection for the whole track (the segment list is replaced and ' \
                  '`segment` is null).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :track_id, in: :path, type: :integer, required: true, description: 'Track ID'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Segment ID'
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          transportation_mode: { type: :string, example: 'driving' },
          reset: { type: :boolean, example: false }
        }
      }

      let(:id) { segment.id }

      response '200', 'segment updated' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:body) { { transportation_mode: 'driving' } }

        schema type: :object,
               properties: track_segments_properties.merge(
                 segment: segment_schema.merge(nullable: true)
               ),
               required: %w[track_id dominant_mode enabled_modes segments segment]

        run_test!
      end

      response '400', 'neither transportation_mode nor reset given' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:body) { {} }

        run_test!
      end

      response '422', 'mode not enabled' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:body) { { transportation_mode: 'hovercraft' } }

        schema type: :object,
               properties: {
                 error: { type: :string, enum: %w[mode_not_enabled reprocess_failed update_failed] },
                 message: { type: :string },
                 enabled_modes: { type: :array, items: { type: :string } }
               },
               required: %w[error message]

        run_test!
      end

      response '404', 'segment not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:body) { { transportation_mode: 'driving' } }
        let(:id) { create(:track_segment, track: create(:track, user: create(:user))).id }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

describe 'Imports API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/imports' do
    get 'Lists imports' do
      tags 'Imports'
      description 'Returns all imports for the authenticated user, ordered by creation date (newest first)'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :page, in: :query, type: :integer, required: false, description: 'Page number'
      parameter name: :per_page, in: :query, type: :integer, required: false,
                description: 'Items per page (default: 25)'

      response '200', 'imports found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer, description: 'Import ID' },
                   name: { type: :string, description: 'Import filename' },
                   source: { type: :string, nullable: true,
                             description: 'Detected source type (gpx, geojson, kml, owntracks, etc.)' },
                   status: { type: :string,
                             description: 'Processing status (created, processing, completed, failed)' },
                   created_at: { type: :string, format: 'date-time' },
                   points_count: { type: :integer, description: 'Number of points imported' },
                   processed: { type: :integer, description: 'Number of points processed so far' },
                   error_message: { type: :string, nullable: true,
                                    description: 'Error message if import failed' }
                 },
                 required: %w[id name status created_at]
               }

        let!(:imports) { create_list(:import, 2, user:) }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end

    post 'Creates an import' do
      tags 'Imports'
      description 'Uploads a file (GPX, GeoJSON, KML, OwnTracks, etc.) and queues it for import processing. ' \
                  'Source type is auto-detected from the file content. ' \
                  'Processing happens asynchronously in the background.'
      consumes 'multipart/form-data'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :file, in: :formData, type: :file, required: true,
                description: 'The file to import (GPX, GeoJSON, KML, OwnTracks JSON, etc.)'

      response '201', 'import created' do
        schema type: :object,
               properties: {
                 id: { type: :integer, description: 'Import ID' },
                 name: { type: :string, description: 'Import filename' },
                 source: { type: :string, nullable: true, description: 'Detected source type' },
                 status: { type: :string, description: 'Processing status' },
                 created_at: { type: :string, format: 'date-time' },
                 points_count: { type: :integer, description: 'Number of points imported' },
                 processed: { type: :integer, description: 'Number of points processed so far' },
                 error_message: { type: :string, nullable: true }
               },
               required: %w[id name status created_at]

        let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '422', 'missing file or validation error' do
        let(:file) { nil }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:file) { fixture_file_upload('gpx/gpx_track_single_segment.gpx', 'application/gpx+xml') }

        run_test!
      end
    end
  end

  path '/api/v1/imports/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true, description: 'Import ID'

    get 'Retrieves an import' do
      tags 'Imports'
      description 'Returns details of a specific import including processing status and point count'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'import found' do
        schema type: :object,
               properties: {
                 id: { type: :integer, description: 'Import ID' },
                 name: { type: :string, description: 'Import filename' },
                 source: { type: :string, nullable: true, description: 'Detected source type' },
                 status: { type: :string, description: 'Processing status' },
                 created_at: { type: :string, format: 'date-time' },
                 points_count: { type: :integer, description: 'Number of points imported' },
                 processed: { type: :integer, description: 'Number of points processed so far' },
                 error_message: { type: :string, nullable: true }
               },
               required: %w[id name status created_at]

        let(:import) { create(:import, user:) }
        let(:id) { import.id }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '404', 'import not found' do
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:id) { create(:import).id }

        run_test!
      end
    end
  end
end

# frozen_string_literal: true

require 'swagger_helper'

describe 'Notes API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/notes' do
    get 'List notes' do
      tags 'Notes'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :attachable_type, in: :query, type: :string, required: false,
                description: 'Filter by attachable type (e.g. Trip)'
      parameter name: :attachable_id, in: :query, type: :integer, required: false,
                description: 'Filter by attachable ID'
      parameter name: :standalone, in: :query, type: :string, required: false,
                description: 'Set to "true" to return only standalone notes'

      response '200', 'notes found' do
        let(:Authorization) { "Bearer #{api_key}" }

        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   title: { type: :string, nullable: true },
                   body: { type: :string, nullable: true },
                   latitude: { type: :number, nullable: true },
                   longitude: { type: :number, nullable: true },
                   attachable_type: { type: :string, nullable: true },
                   attachable_id: { type: :integer, nullable: true },
                   date: { type: :string, nullable: true, format: :date },
                   noted_at: { type: :string, format: :datetime },
                   created_at: { type: :string, format: :datetime },
                   updated_at: { type: :string, format: :datetime }
                 },
                 required: %w[id noted_at]
               }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        run_test!
      end
    end

    post 'Create note' do
      tags 'Notes'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :note, in: :body, schema: {
        type: :object,
        properties: {
          note: {
            type: :object,
            properties: {
              title: { type: :string },
              body: { type: :string },
              latitude: { type: :number },
              longitude: { type: :number },
              attachable_type: { type: :string },
              attachable_id: { type: :integer },
              noted_at: { type: :string, format: :datetime }
            },
            required: %w[noted_at]
          }
        }
      }

      response '201', 'note created' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:note) do
          { note: { body: 'A test note', noted_at: Time.current.iso8601 } }
        end

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 title: { type: :string, nullable: true },
                 body: { type: :string, nullable: true },
                 latitude: { type: :number, nullable: true },
                 longitude: { type: :number, nullable: true },
                 attachable_type: { type: :string, nullable: true },
                 attachable_id: { type: :integer, nullable: true },
                 date: { type: :string, nullable: true, format: :date },
                 noted_at: { type: :string, format: :datetime },
                 created_at: { type: :string, format: :datetime },
                 updated_at: { type: :string, format: :datetime }
               }

        run_test!
      end

      response '422', 'invalid request' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:note) { { note: { body: 'No date' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:note) do
          { note: { body: 'A test note', noted_at: Time.current.iso8601 } }
        end

        run_test!
      end
    end
  end

  path '/api/v1/notes/{id}' do
    get 'Show note' do
      tags 'Notes'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Note ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '200', 'note found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 title: { type: :string, nullable: true },
                 body: { type: :string, nullable: true },
                 latitude: { type: :number, nullable: true },
                 longitude: { type: :number, nullable: true },
                 attachable_type: { type: :string, nullable: true },
                 attachable_id: { type: :integer, nullable: true },
                 date: { type: :string, nullable: true, format: :date },
                 noted_at: { type: :string, format: :datetime },
                 created_at: { type: :string, format: :datetime },
                 updated_at: { type: :string, format: :datetime }
               }

        run_test!
      end

      response '404', 'note not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }

        run_test!
      end
    end

    patch 'Update note' do
      tags 'Notes'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Note ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'
      parameter name: :note, in: :body, schema: {
        type: :object,
        properties: {
          note: {
            type: :object,
            properties: {
              title: { type: :string },
              body: { type: :string },
              latitude: { type: :number },
              longitude: { type: :number },
              noted_at: { type: :string, format: :datetime }
            }
          }
        }
      }

      response '200', 'note updated' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }
        let(:note) { { note: { body: 'Updated note' } } }

        schema type: :object,
               properties: {
                 id: { type: :integer },
                 title: { type: :string, nullable: true },
                 body: { type: :string, nullable: true },
                 latitude: { type: :number, nullable: true },
                 longitude: { type: :number, nullable: true },
                 attachable_type: { type: :string, nullable: true },
                 attachable_id: { type: :integer, nullable: true },
                 date: { type: :string, nullable: true, format: :date },
                 noted_at: { type: :string, format: :datetime },
                 created_at: { type: :string, format: :datetime },
                 updated_at: { type: :string, format: :datetime }
               }

        run_test!
      end

      response '404', 'note not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }
        let(:note) { { note: { body: 'Updated note' } } }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }
        let(:note) { { note: { body: 'Updated note' } } }

        run_test!
      end
    end

    delete 'Delete note' do
      tags 'Notes'
      parameter name: :id, in: :path, type: :integer, required: true, description: 'Note ID'
      parameter name: :Authorization, in: :header, type: :string, required: true, description: 'Bearer token'

      response '200', 'note deleted' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }

        run_test!
      end

      response '404', 'note not found' do
        let(:Authorization) { "Bearer #{api_key}" }
        let(:id) { 999_999 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid-token' }
        let(:test_note) { create(:note, user: user, noted_at: Time.current) }
        let(:id) { test_note.id }

        run_test!
      end
    end
  end
end

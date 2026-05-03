# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Families Locations API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/families/locations' do
    get 'Retrieves family members\' locations' do
      tags 'Families'
      description 'Returns the last known locations of all family members who have enabled location sharing. ' \
                  'Requires the family feature to be enabled and the user to be part of a family.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'family locations found' do
        schema type: :object,
               properties: {
                 locations: {
                   type: :array,
                   description: 'Array of family member location data',
                   items: { type: :object }
                 },
                 updated_at: { type: :string, format: 'date-time', description: 'When the data was last updated' },
                 sharing_enabled: { type: :boolean, description: 'Whether the current user has sharing enabled' }
               }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '404', 'user not in a family' do
        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end

  path '/api/v1/families/locations/history' do
    get 'Retrieves family members\' location history for a time range' do
      tags 'Families'
      description 'Returns historical points for each family member with sharing enabled, between ' \
                  '`start_at` and `end_at`. Both timestamps are required and must be parseable ISO 8601.'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string, required: true,
                description: 'Start of the time range (ISO 8601)'
      parameter name: :end_at, in: :query, type: :string, required: true,
                description: 'End of the time range (ISO 8601)'

      response '200', 'history returned' do
        schema type: :object,
               properties: {
                 members: {
                   type: :array,
                   items: {
                     type: :object,
                     description: 'Per-member historical points'
                   }
                 }
               }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        after { |example| SwaggerResponseExample.capture(example, response) }

        run_test!
      end

      response '400', 'missing or invalid date parameters' do
        schema type: :object, properties: { error: { type: :string } }

        before do
          family = create(:family, creator: user)
          create(:family_membership, :owner, family: family, user: user)
        end

        let(:start_at) { '' }
        let(:end_at) { '' }

        run_test!
      end

      response '403', 'user not in a family' do
        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }
        let(:start_at) { 1.day.ago.iso8601 }
        let(:end_at) { Time.current.iso8601 }

        run_test!
      end
    end
  end
end

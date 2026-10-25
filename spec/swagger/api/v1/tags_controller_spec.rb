# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Tags API', type: :request do
  let(:user) { create(:user) }
  let(:api_key) { user.api_key }

  path '/api/v1/tags/privacy_zones' do
    get 'Retrieves privacy zone tags' do
      tags 'Tags'
      description 'Returns all tags configured as privacy zones, including their associated places'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'privacy zones found' do
        before do
          tag = create(:tag, user:, privacy_radius_meters: 500)
          tag.places << create(:place, user:, latitude: 52.5, longitude: 13.4)
        end

        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   tag_id: { type: :integer, description: 'Tag ID' },
                   tag_name: { type: :string, description: 'Tag name' },
                   tag_icon: { type: :string, nullable: true, description: 'Tag icon' },
                   tag_color: { type: :string, nullable: true, description: 'Tag color' },
                   radius_meters: { type: :integer, nullable: true, description: 'Privacy zone radius in meters' },
                   places: {
                     type: :array,
                     description: 'Places associated with this privacy zone',
                     items: {
                       type: :object,
                       properties: {
                         id: { type: :integer, description: 'Place ID' },
                         name: { type: :string, description: 'Place name' },
                         latitude: { type: :number, description: 'Latitude coordinate' },
                         longitude: { type: :number, description: 'Longitude coordinate' },
                         masked_area: {
                           type: :object,
                           nullable: true,
                           description: 'Circle the map hides around this place. It is larger than the radius and ' \
                                        'shifted off the place, so the place cannot be found from where the map ' \
                                        'stops, and it always covers the full radius around the place.',
                           properties: {
                             latitude: { type: :number },
                             longitude: { type: :number },
                             radius_meters: { type: :integer }
                           },
                           required: %w[latitude longitude radius_meters]
                         }
                       },
                       required: %w[id latitude longitude masked_area]
                     }
                   }
                 }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:api_key) { 'invalid' }

        run_test!
      end
    end
  end
end

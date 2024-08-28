# frozen_string_literal: true

require 'swagger_helper'

describe 'Points API', type: :request do
  path '/api/v1/points' do
    get 'Retrieves all points' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :start_at, in: :query, type: :string,
                description: 'Start date (i.e. 2024-02-03T13:00:03Z or 2024-02-03)'
      parameter name: :end_at, in: :query, type: :string,
                description: 'End date (i.e. 2024-02-03T13:00:03Z or 2024-02-03)'
      parameter name: :page, in: :query, type: :integer, required: false, description: 'Page number'
      parameter name: :per_page, in: :query, type: :integer, required: false, description: 'Number of points per page'
      response '200', 'points found' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:                { type: :integer },
                   battery_status:    { type: :number },
                   ping:              { type: :number },
                   battery:           { type: :number },
                   tracker_id:        { type: :string },
                   topic:             { type: :string },
                   altitude:          { type: :number },
                   longitude:         { type: :number },
                   velocity:          { type: :number },
                   trigger:           { type: :string },
                   bssid:             { type: :string },
                   ssid:              { type: :string },
                   connection:        { type: :string },
                   vertical_accuracy: { type: :number },
                   accuracy:          { type: :number },
                   timestamp:         { type: :number },
                   latitude:          { type: :number },
                   mode:              { type: :number },
                   inrids:            { type: :array },
                   in_regions:        { type: :array },
                   raw_data:          { type: :string },
                   import_id:         { type: :string },
                   city:              { type: :string },
                   country:           { type: :string },
                   created_at:        { type: :string },
                   updated_at:        { type: :string },
                   user_id:           { type: :integer },
                   geodata:           { type: :string },
                   visit_id:          { type: :string }
                 }
               }

        let(:user)      { create(:user) }
        let(:areas)     { create_list(:area, 3, user:) }
        let(:api_key)   { user.api_key }
        let(:start_at)  { Time.zone.now - 1.day }
        let(:end_at)    { Time.zone.now }
        let(:points)    { create_list(:point, 10, user:, timestamp: 2.hours.ago) }

        run_test!
      end
    end
  end

  path '/api/v1/points/{id}' do
    delete 'Deletes a point' do
      tags 'Points'
      produces 'application/json'
      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'
      parameter name: :id, in: :path, type: :string, required: true, description: 'Point ID'

      response '200', 'point deleted' do
        let(:user)    { create(:user) }
        let(:point)   { create(:point, user:) }
        let(:api_key) { user.api_key }
        let(:id)      { point.id }

        run_test!
      end
    end
  end
end

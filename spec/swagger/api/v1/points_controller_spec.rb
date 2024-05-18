# frozen_string_literal: true

require 'swagger_helper'

describe 'Points API', type: :request do
  path '/api/v1/points' do
    post 'Creates a point' do
      request_body_example value: {
        lat: 52.502397,
        lon: 13.356718,
        tid: 'Swagger',
        tst: Time.current.to_i
      }
      tags 'Points'
      consumes 'application/json'
      parameter name: :point, in: :body, schema: {
        type: :object,
        properties: {
          acc:  { type: :number },
          alt:  { type: :number },
          batt: { type: :number },
          bs:   { type: :number },
          cog:  { type: :number },
          lat:  { type: :string, format: :decimal },
          lon:  { type: :string, format: :decimal },
          rad:  { type: :number },
          t:    { type: :string },
          tid:  { type: :string },
          tst:  { type: :number },
          vac:  { type: :number },
          vel:  { type: :number },
          p:    { type: :string, format: :decimal },
          poi:  { type: :string },
          conn: { type: :string },
          tag:  { type: :string },
          topic: { type: :string },
          inregions: { type: :array },
          SSID: { type: :string },
          BSSID: { type: :string },
          created_at: { type: :string },
          inrids: { type: :array },
          m: { type: :number }
        },
        required: %w[lat lon tid tst]
      }

      response '200', 'point created' do
        let(:point) { { lat: 1.0, lon: 2.0, tid: 3, tst: 4 } }

        run_test!
      end

      response '200', 'invalid request' do
        let(:point) { { lat: 1.0 } }

        run_test!
      end
    end
  end
end

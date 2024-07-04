# frozen_string_literal: true

require 'swagger_helper'

describe 'OwnTracks Points API', type: :request do
  path '/api/v1/owntracks/points' do
    post 'Creates a point' do
      request_body_example value: {
        'batt': 85,
        'lon': -74.0060,
        'acc': 8,
        'bs': 2,
        'inrids': [
          '5f1d1b'
        ],
        'BSSID': 'b0:f2:8:45:94:33',
        'SSID': 'Home Wifi',
        'vac': 3,
        'inregions': [
          'home'
        ],
        'lat': 40.7128,
        'topic': 'owntracks/jane/iPhone 12 Pro',
        't': 'p',
        'conn': 'w',
        'm': 1,
        'tst': 1706965203,
        'alt': 41,
        '_type': 'location',
        'tid': 'RO',
        '_http': true,
        'ghash': 'u33d773',
        'isorcv': '2024-02-03T13:00:03Z',
        'isotst': '2024-02-03T13:00:03Z',
        'disptst': '2024-02-03 13:00:03'
      }
      tags 'Points'
      consumes 'application/json'
      parameter name: :point, in: :body, schema: {
        type: :object,
        properties: {
          batt: { type: :number },
          lon: { type: :number },
          acc: { type: :number },
          bs: { type: :number },
          inrids: { type: :array },
          BSSID: { type: :string },
          SSID: { type: :string },
          vac: { type: :number },
          inregions: { type: :array },
          lat: { type: :number },
          topic: { type: :string },
          t: { type: :string },
          conn: { type: :string },
          m: { type: :number },
          tst: { type: :number },
          alt: { type: :number },
          _type: { type: :string },
          tid: { type: :string },
          _http: { type: :boolean },
          ghash: { type: :string },
          isorcv: { type: :string },
          isotst: { type: :string },
          disptst: { type: :string }
        },
        required: %w[owntracks/jane]
      }

      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'Point created' do
        let(:file_path) { 'spec/fixtures/files/owntracks/export.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:point) { json['test']['iphone-12-pro'].first }
        let(:api_key) { create(:user).api_key }

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:file_path) { 'spec/fixtures/files/owntracks/export.json' }
        let(:file) { File.open(file_path) }
        let(:json) { JSON.parse(file.read) }
        let(:point) { json['test']['iphone-12-pro'].first }
        let(:api_key) { nil }

        run_test!
      end
    end
  end
end

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
        'tst': 1_706_965_203,
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
          batt: { type: :number, description: 'Device battery level (percentage)' },
          lon: { type: :number, description: 'Longitude coordinate' },
          acc: { type: :number, description: 'Accuracy of position in meters' },
          bs: { type: :number, description: 'Battery status (0=unknown, 1=unplugged, 2=charging, 3=full)' },
          inrids: { type: :array, description: 'Array of region IDs device is currently in' },
          BSSID: { type: :string, description: 'Connected WiFi access point MAC address' },
          SSID: { type: :string, description: 'Connected WiFi network name' },
          vac: { type: :number, description: 'Vertical accuracy in meters' },
          inregions: { type: :array, description: 'Array of region names device is currently in' },
          lat: { type: :number, description: 'Latitude coordinate' },
          topic: { type: :string, description: 'MQTT topic in format owntracks/user/device' },
          t: { type: :string, description: 'Type of message (p=position, c=circle, etc)' },
          conn: { type: :string, description: 'Connection type (w=wifi, m=mobile, o=offline)' },
          m: { type: :number, description: 'Motion state (0=stopped, 1=moving)' },
          tst: { type: :number, description: 'Timestamp in Unix epoch time' },
          alt: { type: :number, description: 'Altitude in meters' },
          _type: { type: :string, description: 'Internal message type (usually "location")' },
          tid: { type: :string, description: 'Tracker ID used to display the initials of a user' },
          _http: { type: :boolean, description: 'Whether message was sent via HTTP (true) or MQTT (false)' },
          ghash: { type: :string, description: 'Geohash of location' },
          isorcv: { type: :string, description: 'ISO 8601 timestamp when message was received' },
          isotst: { type: :string, description: 'ISO 8601 timestamp of the location fix' },
          disptst: { type: :string, description: 'Human-readable timestamp of the location fix' }
        },
        required: %w[owntracks/jane]
      }

      parameter name: :api_key, in: :query, type: :string, required: true, description: 'API Key'

      response '200', 'Point created' do
        let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
        let(:file) { File.read(file_path) }
        let(:json) { OwnTracks::RecParser.new(file).call }
        let(:point) { json.first }
        let(:api_key) { create(:user).api_key }

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
        let(:file) { File.read(file_path) }
        let(:json) { OwnTracks::RecParser.new(file).call }
        let(:point) { json.first }
        let(:api_key) { nil }

        run_test!
      end
    end
  end
end

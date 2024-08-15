# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::ExportParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: 'owntracks_export.json') }

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(9)
      end

      it 'correctly writes attributes' do
        parser

        expect(Point.first.attributes).to include(
          'latitude' => 40.7128,
          'longitude' => -74.006,
          'battery_status' => 'charging',
          'battery' => 85,
          'ping' => nil,
          'altitude' => 41,
          'accuracy' => 8,
          'vertical_accuracy' => 3,
          'velocity' => nil,
          'connection' => 'wifi',
          'ssid' => 'Home Wifi',
          'bssid' => 'b0:f2:8:45:94:33',
          'trigger' => 'background_event',
          'tracker_id' => 'RO',
          'timestamp' => 1_706_965_203,
          'inrids' => ['5f1d1b'],
          'in_regions' => ['home'],
          'topic' => 'owntracks/test/iPhone 12 Pro',
          'visit_id' => nil,
          'user_id' => user.id,
          'country' => nil,
          'raw_data' => {
            'batt' => 85,
            'lon' => -74.006,
            'acc' => 8,
            'bs' => 2,
            'inrids' => ['5f1d1b'],
            'BSSID' => 'b0:f2:8:45:94:33',
            'SSID' => 'Home Wifi',
            'vac' => 3,
            'inregions' => ['home'],
            'lat' => 40.7128,
            'topic' => 'owntracks/test/iPhone 12 Pro',
            't' => 'p',
            'conn' => 'w',
            'm' => 1,
            'tst' => 1_706_965_203,
            'alt' => 41,
            '_type' => 'location',
            'tid' => 'RO',
            '_http' => true,
            'ghash' => 'u33d773',
            'isorcv' => '2024-02-03T13:00:03Z',
            'isotst' => '2024-02-03T13:00:03Z',
            'disptst' => '2024-02-03 13:00:03'
          }
        )
      end
    end
  end
end

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
          'latitude' => 52.225,
          'longitude' => 13.332,
          'battery_status' => 'charging',
          'battery' => 94,
          'ping' => '100.266',
          'altitude' => 36,
          'accuracy' => 10,
          'vertical_accuracy' => 4,
          'velocity' => '0',
          'connection' => 'wifi',
          'ssid' => 'Home Wifi',
          'bssid' => 'b0:f2:8:45:94:33',
          'trigger' => 'background_event',
          'tracker_id' => 'RO',
          'timestamp' => 1_709_283_789,
          'inrids' => ['5f1d1b'],
          'in_regions' => ['home'],
          'topic' => 'owntracks/test/iPhone 12 Pro',
          'visit_id' => nil,
          'user_id' => user.id,
          'raw_data' => {
            'm' => 1,
            'p' => 100.266,
            't' => 'p',
            'bs' => 2,
            'acc' => 10,
            'alt' => 36,
            'lat' => 52.225,
            'lon' => 13.332,
            'tid' => 'RO',
            'tst' => 1_709_283_789,
            'vac' => 4,
            'vel' => 0,
            'SSID' => 'Home Wifi',
            'batt' => 94,
            'conn' => 'w',
            'BSSID' => 'b0:f2:8:45:94:33',
            '_http' => true,
            '_type' => 'location',
            'topic' => 'owntracks/test/iPhone 12 Pro',
            'inrids' => ['5f1d1b'],
            'inregions' => ['home']
          }
        )
      end
    end
  end
end

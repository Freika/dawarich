# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::Importer do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: '2024-03.rec') }
    let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }
    let(:file) { Rack::Test::UploadedFile.new(file_path, 'text/plain') }

    before do
      import.file.attach(io: File.open(file_path), filename: '2024-03.rec', content_type: 'text/plain')
    end

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(9)
      end

      it 'correctly writes attributes' do
        parser

        point = Point.first
        expect(point.lonlat.x).to be_within(0.001).of(13.332)
        expect(point.lonlat.y).to be_within(0.001).of(52.225)
        expect(point.attributes.except('lonlat')).to include(
          'battery_status' => 'charging',
          'battery' => 94,
          'ping' => '100.266',
          'altitude' => 36,
          'accuracy' => 10,
          'vertical_accuracy' => 4,
          'velocity' => '1.4',
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
          'country' => nil,
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
            'vel' => 5,
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

      it 'correctly converts speed' do
        parser

        expect(Point.first.velocity).to eq('1.4')
      end
    end

    context 'when file is old' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2023-02_old.rec') }

      it 'creates points' do
        expect { parser }.to change { Point.count }.by(9)
      end
    end
  end
end

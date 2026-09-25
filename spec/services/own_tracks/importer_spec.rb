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

        point = user.points.first
        expect(point.lonlat.x).to be_within(0.001).of(13.332)
        expect(point.lonlat.y).to be_within(0.001).of(52.225)
        expect(point.attributes.except('lonlat')).to include(
          'battery' => 94,
          'altitude' => 36,
          'accuracy' => 10,
          'vertical_accuracy' => 4,
          'velocity' => 1.4,
          'timestamp' => 1_709_283_789,
          'visit_id' => nil,
          'user_id' => user.id,
          'motion_data' => { 'm' => 1, '_type' => 'location' }
        )
        # The device combo reads through the point_sources dimension.
        expect(point.battery_status).to eq('charging')
        expect(point.connection).to eq('wifi')
        expect(point.ssid).to eq('Home Wifi')
        expect(point.bssid).to eq('b0:f2:8:45:94:33')
        expect(point.trigger).to eq('background_event')
        expect(point.tracker_id).to eq('RO')
        expect(point.inrids).to eq(['5f1d1b'])
        expect(point.in_regions).to eq(['home'])
        expect(point.topic).to eq('owntracks/test/iPhone 12 Pro')
      end

      it 'does not persist raw_data for imported points' do
        parser

        expect(Point.where(import_id: import.id).pluck(:raw_data).uniq).to eq([{}])
      end

      it 'correctly converts speed' do
        parser

        expect(user.points.first.velocity).to eq(1.4)
      end

      it 'updates the import processed counter' do
        parser

        expect(import.reload.processed).to eq(9)
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

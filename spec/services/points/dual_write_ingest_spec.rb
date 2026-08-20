# frozen_string_literal: true

require 'rails_helper'

# C4: every ingest path must stamp source_id/motion_id as it writes, or new
# points land behind the backfill cursor and stay unstamped forever.
RSpec.describe 'dual-write ingest' do
  let(:user) { create(:user) }

  describe Points::Create do
    let(:params) do
      {
        locations: [
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [13.4, 52.5] },
            properties: {
              timestamp: '2026-08-20T10:00:00Z',
              horizontal_accuracy: 5,
              device_id: 'pixel-8',
              battery_state: 'unplugged',
              battery_level: 0.9,
              wifi: 'home-wifi',
              motion: %w[walking]
            }
          }
        ]
      }
    end

    it 'stamps the dimension FKs on points created through the API' do
      described_class.new(user, params).call

      point = user.points.order(:id).last
      expect(point.source_id).to be_present
      expect(point.motion_id).to be_present
    end

    it 'points the FK at the row whose combo matches' do
      described_class.new(user, params).call

      point = user.points.order(:id).last
      expect(PointSource.find(point.source_id).tracker_id).to eq('pixel-8')
    end
  end

  describe Imports::BulkInsertable do
    let(:importer) do
      Class.new do
        include Imports::BulkInsertable

        def importer_name = 'spec'
        def record_batch_counters(*) = nil
        def on_bulk_insert_error(error) = raise(error)
        def run(batch) = bulk_insert_points(batch)
      end.new
    end

    let(:batch) do
      [
        { user_id: user.id, lonlat: 'POINT(13.4 52.5)', timestamp: 1_760_000_000,
          tracker_id: 'gpx-import', motion_data: { 'activity' => 'cycling' } },
        { user_id: user.id, lonlat: 'POINT(13.5 52.6)', timestamp: 1_760_000_060,
          tracker_id: 'gpx-import', motion_data: { 'activity' => 'cycling' } }
      ]
    end

    it 'stamps the dimension FKs on imported points' do
      importer.run(batch)

      expect(user.points.where(source_id: nil)).to be_empty
      expect(user.points.where(motion_id: nil)).to be_empty
    end

    it 'shares one dimension row across a batch with one combo' do
      expect { importer.run(batch) }.to change(PointSource, :count).by(1)
    end
  end
end

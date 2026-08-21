# frozen_string_literal: true

require 'rails_helper'

# C4: every ingest path must stamp source_id as it writes, or new
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

    it 'stamps the dimension FK on points created through the API' do
      described_class.new(user, params).call

      point = user.points.order(:id).last
      expect(point.source_id).to be_present
    end

    it 'points the FK at the row whose combo matches' do
      described_class.new(user, params).call

      point = user.points.order(:id).last
      expect(PointSource.find(point.source_id).tracker_id).to eq('pixel-8')
    end
  end

  # The three live trackers each have their own creator calling
  # archival_safe_upsert_all directly — none of them pass through
  # Points::Create, so each must stamp for itself.
  describe OwnTracks::PointCreator do
    let(:params) do
      OwnTracks::RecParser.new(File.read('spec/fixtures/files/owntracks/2024-03.rec')).call.first
    end

    it 'stamps the dimension FK on live OwnTracks points' do
      described_class.new(params, user.id).call

      expect(user.points.order(:id).last.source_id).to be_present
    end
  end

  describe Traccar::PointCreator do
    let(:params) do
      {
        device_id: 'iphone-frey',
        location: {
          timestamp: '2026-04-23T12:34:56Z',
          latitude: 52.52, longitude: 13.405,
          accuracy: 5, speed: 1.4, altitude: 42
        },
        battery: { level: 0.85, is_charging: true },
        activity: { type: 'walking' }
      }
    end

    it 'stamps the dimension FK on live Traccar points' do
      described_class.new(params, user.id).call

      expect(user.points.order(:id).last.source_id).to be_present
    end
  end

  describe Overland::PointsCreator do
    let(:params) { JSON.parse(File.read('spec/fixtures/files/overland/geodata.json')) }

    it 'stamps the dimension FK on live Overland points' do
      described_class.new(params, user.id).call

      expect(user.points.where(source_id: nil)).to be_empty
      expect(user.points.count).to be_positive
    end
  end

  # Bypasses Imports::BulkInsertable with its own upsert_all.
  describe GoogleMaps::SemanticHistoryImporter do
    let(:import) { create(:import, user: user) }
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/google/location-history/with_activitySegment_with_startLocation.json')
    end

    before do
      import.file.attach(io: File.open(file_path), filename: 'semantic_history.json',
                         content_type: 'application/json')
    end

    it 'stamps the dimension FK on Google semantic history points' do
      described_class.new(import, user.id).call

      expect(user.points.count).to be_positive
      expect(user.points.where(source_id: nil)).to be_empty
    end
  end

  # Bypasses Imports::BulkInsertable with its own upsert_all.
  describe Users::ImportData::Points do
    let(:points_data) do
      [
        { 'timestamp' => 1_640_995_200, 'lonlat' => 'POINT(13.4050 52.5200)',
          'tracker_id' => 'restored-device' },
        { 'timestamp' => 1_640_995_260, 'lonlat' => 'POINT(13.4060 52.5210)',
          'tracker_id' => 'restored-device' }
      ]
    end

    it 'stamps the dimension FK on points restored from a user data dump' do
      described_class.new(user, points_data).call

      expect(user.points.count).to eq(2)
      expect(user.points.where(source_id: nil)).to be_empty
      expect(user.points.pluck(:source_id).uniq.size).to eq(1)
    end
  end

  describe Imports::BulkInsertable do
    let(:import) { create(:import, user: user) }

    # The concern expects its host to expose the import it is writing for —
    # bulk_insert_points bumps the tile epoch off import.user_id.
    let(:importer) do
      Class.new do
        include Imports::BulkInsertable

        attr_reader :import

        def initialize(import) = @import = import
        def importer_name = 'spec'
        def record_batch_counters(*) = nil
        def on_bulk_insert_error(error) = raise(error)
        def run(batch) = bulk_insert_points(batch)
      end.new(import)
    end

    let(:batch) do
      [
        { user_id: user.id, lonlat: 'POINT(13.4 52.5)', timestamp: 1_760_000_000,
          tracker_id: 'gpx-import', motion_data: { 'activity' => 'cycling' } },
        { user_id: user.id, lonlat: 'POINT(13.5 52.6)', timestamp: 1_760_000_060,
          tracker_id: 'gpx-import', motion_data: { 'activity' => 'cycling' } }
      ]
    end

    it 'stamps the dimension FK on imported points' do
      importer.run(batch)

      expect(user.points.where(source_id: nil)).to be_empty
    end

    it 'shares one dimension row across a batch with one combo' do
      expect { importer.run(batch) }.to change(PointSource, :count).by(1)
    end
  end
end

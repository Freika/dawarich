# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kml::Importer do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id, file_path).call }

    let(:user) { create(:user) }
    let(:import) { create(:import, user:, name: 'test.kml', source: 'kml') }

    context 'when file has Point placemarks with timestamps' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/points_with_timestamps.kml').to_s }

      it 'creates points' do
        expect { parser }.to change(Point, :count).by(3)
      end

      it 'creates points with correct data' do
        parser

        point = user.points.order(:timestamp).first

        expect(point.lat).to eq(37.4220)
        expect(point.lon).to eq(-122.0841)
        expect(point.altitude).to eq(10)
        expect(point.timestamp).to eq(Time.zone.parse('2024-01-15T12:00:00Z').to_i)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).at_least(1).time

        parser
      end
    end

    context 'when file has LineString (track)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/linestring_track.kml').to_s }

      it 'creates points from linestring coordinates' do
        expect { parser }.to change(Point, :count).by(5)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).at_least(1).time

        parser
      end
    end

    context 'when file has gx:Track (Google Earth extension)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/gx_track.kml').to_s }

      it 'creates points from gx:Track with coordinated when/coord pairs' do
        expect { parser }.to change(Point, :count).by(4)
      end

      it 'creates points with correct timestamps' do
        parser

        points = user.points.order(:timestamp)

        expect(points.first.timestamp).to eq(Time.zone.parse('2024-01-20T08:00:00Z').to_i)
        expect(points.last.timestamp).to eq(Time.zone.parse('2024-01-20T08:03:00Z').to_i)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).at_least(1).time

        parser
      end
    end

    context 'when file has MultiGeometry' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/multigeometry.kml').to_s }

      it 'creates points from all geometries in MultiGeometry' do
        expect { parser }.to change(Point, :count).by(6)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).at_least(1).time

        parser
      end
    end

    context 'when file has ExtendedData with speed' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/extended_data.kml').to_s }

      it 'creates points with velocity from ExtendedData' do
        parser

        point = user.points.first

        expect(point.velocity).to eq('5.5')
      end

      it 'stores empty raw_data' do
        parser

        point = user.points.first

        expect(point.raw_data).to eq({})
      end
    end

    context 'when file has TimeSpan' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/timespan.kml').to_s }

      it 'uses TimeSpan begin as timestamp' do
        parser

        point = user.points.first

        expect(point.timestamp).to eq(Time.zone.parse('2024-01-10T09:00:00Z').to_i)
      end
    end

    context 'when file has nested folders' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/nested_folders.kml').to_s }

      it 'processes all placemarks regardless of nesting' do
        expect { parser }.to change(Point, :count).by(4)
      end
    end

    context 'when coordinates are missing required fields' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/invalid_coordinates.kml').to_s }

      it 'skips invalid coordinates' do
        expect { parser }.not_to change(Point, :count)
      end
    end

    context 'when processing large file in batches' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/large_track.kml').to_s }

      it 'processes points' do
        expect { parser }.to change(Point, :count).by(20)
      end
    end

    context 'when importing KMZ file (compressed KML)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/points_with_timestamps.kmz').to_s }

      it 'extracts and processes KML from KMZ archive' do
        expect { parser }.to change(Point, :count).by(3)
      end

      it 'creates points with correct data from extracted KML' do
        parser

        point = user.points.order(:timestamp).first

        expect(point.lat).to eq(37.4220)
        expect(point.lon).to eq(-122.0841)
        expect(point.altitude).to eq(10)
        expect(point.timestamp).to eq(Time.zone.parse('2024-01-15T12:00:00Z').to_i)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).at_least(1).time

        parser
      end
    end

    context 'when import fails' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/kml/points_with_timestamps.kml').to_s }

      before do
        allow(Point).to receive(:upsert_all).and_raise(StandardError.new('Database error'))
      end

      it 'creates an error notification' do
        expect { parser }.to change(Notification, :count).by(1)
      end

      it 'creates notification with error details' do
        parser

        notification = Notification.last

        expect(notification.user_id).to eq(user.id)
        expect(notification.title).to eq('KML Import Error')
        expect(notification.kind).to eq('error')
        expect(notification.content).to include('Database error')
      end
    end
  end
end

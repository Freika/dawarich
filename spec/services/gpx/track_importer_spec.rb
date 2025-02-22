# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Gpx::TrackImporter do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }
    let(:raw_data) { Hash.from_xml(File.read(file_path)) }
    let(:import) { create(:import, user:, name: 'gpx_track.gpx', raw_data:) }

    context 'when file has a single segment' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(10)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(10).times

        parser
      end
    end

    context 'when file has multiple segments' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_multiple_segments.gpx') }

      it 'creates points' do
        expect { parser }.to change { Point.count }.by(43)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(43).times

        parser
      end
    end

    context 'when file has multiple tracks' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_multiple_tracks.gpx') }

      it 'creates points' do
        expect { parser }.to change { Point.count }.by(34)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(34).times

        parser
      end

      it 'creates points with correct data' do
        parser

        expect(Point.first.lat).to eq(37.1722103)
        expect(Point.first.lon).to eq(-3.55468)
        expect(Point.first.altitude).to eq(1066)
        expect(Point.first.timestamp).to eq(Time.zone.parse('2024-04-21T10:19:55Z').to_i)
        expect(Point.first.velocity).to eq('2.9')
      end
    end

    context 'when file exported from Garmin' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/garmin_example.gpx') }

      it 'creates points with correct data' do
        parser

        expect(Point.first.lat).to eq(10.758321212464024)
        expect(Point.first.lon).to eq(106.64234449272531)
        expect(Point.first.altitude).to eq(17)
        expect(Point.first.timestamp).to eq(1_730_626_211)
        expect(Point.first.velocity).to eq('2.8')
      end
    end

    context 'when file exported from Arc' do
      context 'when file has empty tracks' do
        let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/arc_example.gpx') }

        it 'creates points' do
          expect { parser }.to change { Point.count }.by(6)
        end
      end
    end
  end
end

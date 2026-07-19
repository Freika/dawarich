# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Gpx::TrackImporter do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }
    let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/xml') }
    let(:import) { create(:import, user:, name: 'gpx_track.gpx', source: 'gpx') }

    before do
      import.file.attach(file)
    end

    context 'when file has a single segment' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(10)
      end

      it 'stores altitude_decimal when supported' do
        parser

        expect(user.points.order(:timestamp).first.altitude_decimal).to eq(BigDecimal('824.93'))
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(1).time

        parser
      end
    end

    context 'when altitude_decimal is not supported' do
      let(:upserted_rows) { [] }

      before do
        allow(Point).to receive(:altitude_decimal_supported?).and_return(false)
        allow(Point).to receive(:upsert_all).and_wrap_original do |original, records, **options|
          upserted_rows.concat(records)
          original.call(records, **options)
        end
      end

      it 'imports points without passing altitude_decimal to upsert_all' do
        expect { parser }.to change { Point.count }.by(10)

        expect(upserted_rows).not_to be_empty
        expect(upserted_rows).to all(satisfy { |attrs| attrs.key?(:altitude) && !attrs.key?(:altitude_decimal) })
        expect(user.points.order(:timestamp).first.read_attribute(:altitude)).to be_present
      end
    end

    context 'when file has multiple segments' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_multiple_segments.gpx') }

      it 'creates points' do
        expect { parser }.to change { Point.count }.by(43)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(1).time

        parser
      end
    end

    context 'when file has multiple tracks' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_multiple_tracks.gpx') }

      it 'creates points' do
        expect { parser }.to change { Point.count }.by(34)
      end

      it 'broadcasts importing progress' do
        expect_any_instance_of(Imports::Broadcaster).to receive(:broadcast_import_progress).exactly(1).time

        parser
      end

      it 'creates points with correct data' do
        parser

        point = user.points.first

        expect(point.lat).to eq(37.1722103)
        expect(point.lon).to eq(-3.55468)
        expect(point.altitude).to eq(1066.4)
        expect(point.timestamp).to eq(Time.zone.parse('2024-04-21T10:19:55Z').to_i)
        expect(point.velocity).to eq('2.9')
      end

      it 'does not persist raw_data for imported points' do
        parser

        expect(user.points.pluck(:raw_data).uniq).to eq([{}])
      end
    end

    context 'when file exported from Garmin' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/garmin_example.gpx') }

      it 'creates points with correct data' do
        parser

        point = user.points.first

        expect(point.lat).to eq(10.758321212464024)
        expect(point.lon).to eq(106.64234449272531)
        expect(point.altitude).to eq(17.63)
        expect(point.timestamp).to eq(1_730_626_211)
        expect(point.velocity).to eq('2.8')
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

    context 'when trackpoints have blank or missing elevation' do
      let(:file_path) { gpx_path }
      let(:gpx_path) do
        file = Tempfile.new(['gpx_blank_elevation', '.gpx'])
        file.write(gpx_content)
        file.close
        file.path
      end
      let(:gpx_content) do
        <<~GPX
          <?xml version="1.0" encoding="UTF-8"?>
          <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
            <trk>
              <trkseg>
                <trkpt lat="51.0" lon="7.0">
                  <ele></ele>
                  <time>2026-01-01T00:00:00Z</time>
                </trkpt>
                <trkpt lat="51.1" lon="7.1">
                  <time>2026-01-01T00:01:00Z</time>
                </trkpt>
              </trkseg>
            </trk>
          </gpx>
        GPX
      end

      after { FileUtils.rm_f(gpx_path) }

      it 'imports points with zero elevation' do
        expect { parser }.to change { Point.count }.by(2)

        expect(user.points.order(:timestamp).pluck(:altitude_decimal)).to eq([BigDecimal('0.0'), BigDecimal('0.0')])
      end
    end
  end
end

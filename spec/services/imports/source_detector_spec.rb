# frozen_string_literal: true

require 'rails_helper'
require 'zip'
require 'tempfile'

RSpec.describe Imports::SourceDetector do
  let(:detector) { described_class.new(file_content, filename) }
  let(:filename) { nil }

  describe '#detect_source' do
    context 'with Google Semantic History format' do
      let(:file_content) { file_fixture('google/semantic_history.json').read }

      it 'detects google_semantic_history format' do
        expect(detector.detect_source).to eq(:google_semantic_history)
      end
    end

    context 'with Google Records format' do
      let(:file_content) { file_fixture('google/records.json').read }

      it 'detects google_records format' do
        expect(detector.detect_source).to eq(:google_records)
      end
    end

    context 'with Google Phone Takeout format' do
      let(:file_content) { file_fixture('google/phone-takeout_w_3_duplicates.json').read }

      it 'detects google_phone_takeout format' do
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with Google Phone Takeout array format' do
      let(:file_content) { file_fixture('google/location-history.json').read }

      it 'detects google_phone_takeout format' do
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with GeoJSON format' do
      let(:file_content) { file_fixture('geojson/export.json').read }

      it 'detects geojson format' do
        expect(detector.detect_source).to eq(:geojson)
      end
    end

    context 'with OwnTracks REC file' do
      let(:file_content) { file_fixture('owntracks/2024-03.rec').read }
      let(:filename) { 'test.rec' }

      it 'detects owntracks format' do
        expect(detector.detect_source).to eq(:owntracks)
      end
    end

    context 'with OwnTracks content without .rec extension' do
      let(:file_content) { '{"_type":"location","lat":52.225,"lon":13.332}' }
      let(:filename) { 'test.json' }

      it 'detects owntracks format based on content' do
        expect(detector.detect_source).to eq(:owntracks)
      end
    end

    context 'with GPX file' do
      let(:file_content) { file_fixture('gpx/gpx_track_single_segment.gpx').read }
      let(:filename) { 'test.gpx' }

      it 'detects gpx format' do
        expect(detector.detect_source).to eq(:gpx)
      end
    end

    context 'with KML file' do
      let(:file_content) { file_fixture('kml/points_with_timestamps.kml').read }
      let(:filename) { 'test.kml' }

      it 'detects kml format' do
        expect(detector.detect_source).to eq(:kml)
      end
    end

    context 'with invalid JSON' do
      let(:file_content) { 'invalid json content' }

      it 'returns nil for invalid JSON' do
        expect(detector.detect_source).to be_nil
      end
    end

    context 'with unknown JSON format' do
      let(:file_content) { '{"unknown": "format", "data": []}' }

      it 'returns nil for unknown format' do
        expect(detector.detect_source).to be_nil
      end
    end

    context 'with empty content' do
      let(:file_content) { '' }

      it 'returns nil for empty content' do
        expect(detector.detect_source).to be_nil
      end
    end

    context 'ZIP file detection' do
      it 'detects ZIP by PK magic bytes' do
        zip_file = Tempfile.new(['test', '.zip'])
        Zip::File.open(zip_file.path, create: true) do |zipfile|
          zipfile.get_output_stream('test.txt') { |f| f.write('hello') }
        end

        detector = described_class.new_from_file_header(zip_file.path)
        expect(detector.detect_source).to eq(:zip)
      ensure
        zip_file&.close
        zip_file&.unlink
      end

      it 'does not detect ZIP without .zip extension' do
        non_zip = Tempfile.new(['test', '.dat'])
        Zip::File.open(non_zip.path, create: true) do |zipfile|
          zipfile.get_output_stream('test.txt') { |f| f.write('hello') }
        end

        detector = described_class.new_from_file_header(non_zip.path)
        expect(detector.detect_source).not_to eq(:zip)
      ensure
        non_zip&.close
        non_zip&.unlink
      end
    end

    context 'FIT file detection' do
      it 'detects FIT by .FIT signature at bytes 8-11' do
        # Use a tempfile to avoid overwriting the real fixture
        fit_file = Tempfile.new(['test', '.fit'])
        header = "#{[14, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00].pack('C*')}.FIT#{[0x00, 0x00].pack('C*')}"
        File.write(fit_file.path, header, mode: 'wb')

        detector = described_class.new_from_file_header(fit_file.path)
        expect(detector.detect_source).to eq(:fit)
      ensure
        fit_file&.close
        fit_file&.unlink
      end

      it 'does not detect FIT without .fit extension' do
        file = Tempfile.new(['test', '.dat'])
        header = "#{[14, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00].pack('C*')}.FIT#{[0x00, 0x00].pack('C*')}"
        File.write(file.path, header, mode: 'wb')

        detector = described_class.new_from_file_header(file.path)
        expect(detector.detect_source).not_to eq(:fit)
      ensure
        file&.close
        file&.unlink
      end
    end

    context 'TCX file detection' do
      it 'detects TCX by TrainingCenterDatabase tag' do
        tcx_path = Rails.root.join('spec/fixtures/files/tcx/running.tcx').to_s
        FileUtils.mkdir_p(File.dirname(tcx_path))
        File.write(tcx_path, <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
            <Activities>
              <Activity Sport="Running">
                <Lap StartTime="2024-01-01T10:00:00.000Z">
                  <Track>
                    <Trackpoint>
                      <Time>2024-01-01T10:00:00.000Z</Time>
                      <Position>
                        <LatitudeDegrees>52.520</LatitudeDegrees>
                        <LongitudeDegrees>13.405</LongitudeDegrees>
                      </Position>
                    </Trackpoint>
                  </Track>
                </Lap>
              </Activity>
            </Activities>
          </TrainingCenterDatabase>
        XML

        detector = described_class.new_from_file_header(tcx_path)
        expect(detector.detect_source).to eq(:tcx)
      end

      it 'does not detect TCX without .tcx extension' do
        file = Tempfile.new(['test', '.xml'])
        file.write('<TrainingCenterDatabase><Activities></Activities></TrainingCenterDatabase>')
        file.rewind

        detector = described_class.new_from_file_header(file.path)
        expect(detector.detect_source).not_to eq(:tcx)
      ensure
        file&.close
        file&.unlink
      end
    end

    context 'CSV file detection' do
      it 'detects CSV with recognized headers' do
        csv_path = Rails.root.join('spec/fixtures/files/csv/gpslogger.csv').to_s
        detector = described_class.new_from_file_header(csv_path)
        expect(detector.detect_source).to eq(:csv)
      end

      it 'does not detect CSV with unrecognized headers' do
        file = Tempfile.new(['bad', '.csv'])
        file.write("foo,bar,baz\n1,2,3\n")
        file.rewind

        detector = described_class.new_from_file_header(file.path)
        expect(detector.detect_source).not_to eq(:csv)
      ensure
        file&.close
        file&.unlink
      end

      it 'does not detect CSV without .csv extension' do
        file = Tempfile.new(['test', '.txt'])
        file.write("lat,lon,elevation\n52.52,13.40,34.0\n")
        file.rewind

        detector = described_class.new_from_file_header(file.path)
        expect(detector.detect_source).not_to eq(:csv)
      ensure
        file&.close
        file&.unlink
      end
    end
  end

  describe 'raw content fallback for truncated JSON' do
    context 'with deeply nested truncated Google Phone Takeout' do
      let(:file_content) do
        # Simulates 8KB read truncating mid-string in deeply nested structure
        '{"semanticSegments": [{"startTime": "2013-03-16T03:00:00.000+01:00", ' \
        '"timelinePath": [{"point": "43.7283\u00b0, 10.4047\u00b0", "time": "2013-03-16T04:15'
      end

      it 'detects google_phone_takeout via raw content fallback' do
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with truncated Google Phone Takeout array format' do
      let(:file_content) do
        # Simulates 8KB read truncating mid-string in array-format location-history.json
        '[{"endTime": "2023-08-27T17:04:26.999-05:00", "startTime": "2023-08-27T15:48:56.000-05:00", ' \
        '"visit": {"hierarchyLevel": "0", "topCandidate": {"probability": "0.785181", ' \
        '"semanticType": "Unknown", "placeID": "ChIJxxP_Qwb2aIYRTwDNDLkUmD0", ' \
        '"placeLocation": "geo:27.720022,-97'
      end

      it 'detects google_phone_takeout via raw content fallback' do
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with truncated Google Records' do
      let(:file_content) do
        '{"locations": [{"latitudeE7": 525200000, "longitudeE7": 134000000, "timestamp": "2024-01'
      end

      it 'detects google_records via raw content fallback' do
        expect(detector.detect_source).to eq(:google_records)
      end
    end

    context 'with truncated Google Semantic History' do
      let(:file_content) do
        '{"timelineObjects": [{"activitySegment": {"duration": {"startTimestamp": "2024-01'
      end

      it 'detects google_semantic_history via raw content fallback' do
        expect(detector.detect_source).to eq(:google_semantic_history)
      end
    end

    context 'with truncated GeoJSON' do
      let(:file_content) do
        '{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point'
      end

      it 'detects geojson via raw content fallback' do
        expect(detector.detect_source).to eq(:geojson)
      end
    end
  end

  describe '#detect_source!' do
    context 'with valid format' do
      let(:file_content) { file_fixture('google/records.json').read }

      it 'returns the detected format' do
        expect(detector.detect_source!).to eq(:google_records)
      end
    end

    context 'with unknown format' do
      let(:file_content) { '{"unknown": "format"}' }

      it 'raises UnknownSourceError' do
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError,
          'Unable to detect file format'
        )
      end
    end
  end

  describe '.new_from_file_header' do
    context 'with Google Records file' do
      let(:fixture_path) { file_fixture('google/records.json').to_s }

      it 'detects source correctly from file path' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:google_records)
      end

      it 'can detect source efficiently from file' do
        detector = described_class.new_from_file_header(fixture_path)

        # Verify it can detect correctly using file-based approach
        expect(detector.detect_source).to eq(:google_records)
      end
    end

    context 'with GeoJSON file' do
      let(:fixture_path) { file_fixture('geojson/export.json').to_s }

      it 'detects source correctly from file path' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:geojson)
      end
    end

    context 'with KML file' do
      let(:fixture_path) { file_fixture('kml/points_with_timestamps.kml').to_s }

      it 'detects source correctly from file path' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:kml)
      end
    end
  end

  describe 'detection accuracy with real fixture files' do
    shared_examples 'detects format correctly' do |expected_format, fixture_path|
      it "detects #{expected_format} format for #{fixture_path}" do
        file_content = file_fixture(fixture_path).read
        filename = File.basename(fixture_path)
        detector = described_class.new(file_content, filename)

        expect(detector.detect_source).to eq(expected_format)
      end
    end

    # Test various Google Semantic History variations
    include_examples 'detects format correctly', :google_semantic_history,
                     'google/location-history/with_activitySegment_with_startLocation.json'
    include_examples 'detects format correctly', :google_semantic_history,
                     'google/location-history/with_placeVisit_with_location_with_coordinates.json'

    # Test GeoJSON variations
    include_examples 'detects format correctly', :geojson, 'geojson/export_same_points.json'
    include_examples 'detects format correctly', :geojson, 'geojson/gpslogger_example.json'

    # Test GPX files
    include_examples 'detects format correctly', :gpx, 'gpx/arc_example.gpx'
    include_examples 'detects format correctly', :gpx, 'gpx/garmin_example.gpx'
    include_examples 'detects format correctly', :gpx, 'gpx/gpx_track_multiple_segments.gpx'

    # Test KML files
    include_examples 'detects format correctly', :kml, 'kml/points_with_timestamps.kml'
    include_examples 'detects format correctly', :kml, 'kml/linestring_track.kml'
    include_examples 'detects format correctly', :kml, 'kml/gx_track.kml'
    include_examples 'detects format correctly', :kml, 'kml/multigeometry.kml'
  end
end

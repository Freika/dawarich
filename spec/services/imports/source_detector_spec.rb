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
        '"timelinePath": [{"point": "43.7283°, 10.4047°", "time": "2013-03-16T04:15'
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

  describe 'edge cases discovered from production failures' do
    context 'with bare-array Google Phone Takeout starting with timelinePath' do
      let(:fixture_path) { file_fixture('google/edge_cases/phone_takeout_array_timeline_path.json').to_s }

      it 'detects google_phone_takeout' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with UTF-8 BOM prefix' do
      let(:fixture_path) { file_fixture('google/edge_cases/semantic_history_with_bom.json').to_s }

      it 'detects google_semantic_history despite BOM' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:google_semantic_history)
      end
    end

    context 'with JSON markers beyond the 8KB header window' do
      let(:tmp_path) do
        path = Tempfile.new(['phone_takeout_large', '.json']).path
        big_visit_padding = 'x' * 12_000
        File.write(path, <<~JSON)
          [
            {
              "endTime": "2025-07-29T15:00:00.000Z",
              "startTime": "2025-07-29T13:00:00.000Z",
              "visit": {
                "padding": "#{big_visit_padding}",
                "topCandidate": {
                  "placeID": "ChIJTest",
                  "placeLocation": "geo:29.725358,-95.482259"
                }
              }
            }
          ]
        JSON
        path
      end

      it 'detects google_phone_takeout via raw content fallback' do
        detector = described_class.new_from_file_header(tmp_path)
        expect(detector.detect_source).to eq(:google_phone_takeout)
      end
    end

    context 'with quoted CSV headers' do
      let(:fixture_path) { file_fixture('csv/quoted_headers.csv').to_s }

      it 'detects csv despite quote characters around headers' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:csv)
      end
    end

    context 'with Polarsteps locations.json (official format)' do
      let(:fixture_path) { file_fixture('polarsteps/locations.json').to_s }

      it 'detects polarsteps' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:polarsteps)
      end
    end

    context 'with Polarsteps segments array (extended format)' do
      let(:fixture_path) { file_fixture('polarsteps/segments.json').to_s }

      it 'detects polarsteps' do
        detector = described_class.new_from_file_header(fixture_path)
        expect(detector.detect_source).to eq(:polarsteps)
      end
    end

    context 'with a zero-byte file' do
      let(:tmp_path) { Tempfile.new(['empty', '.json']).path }

      it 'returns nil instead of raising' do
        File.write(tmp_path, '')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source }.not_to raise_error
        expect(detector.detect_source).to be_nil
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

    context 'with Google timelineEdits format (recognized but unsupported)' do
      let(:fixture_path) { file_fixture('google/edge_cases/timeline_edits.json').to_s }

      it 'raises UnknownSourceError with a format-specific message' do
        detector = described_class.new_from_file_header(fixture_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError,
          /Google Timeline Edits format/
        )
      end
    end

    context 'with Google Maps device settings file' do
      let(:fixture_path) { file_fixture('google/edge_cases/device_settings.json').to_s }

      it 'raises UnknownSourceError mentioning settings vs location data' do
        detector = described_class.new_from_file_header(fixture_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError,
          /settings/i
        )
      end
    end

    context 'with encrypted Timeline placeholder text' do
      let(:fixture_path) { file_fixture('unknown/encrypted_timeline_placeholder.txt').to_s }

      it 'raises UnknownSourceError mentioning encryption' do
        detector = described_class.new_from_file_header(fixture_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError,
          /encrypt/i
        )
      end
    end

    context 'with HTML archive contents file' do
      let(:fixture_path) { file_fixture('unknown/archive_contents.html').to_s }

      it 'raises UnknownSourceError mentioning HTML' do
        detector = described_class.new_from_file_header(fixture_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError,
          /HTML/i
        )
      end
    end

    context 'with empty 0-byte file' do
      let(:tmp_path) { Tempfile.new(['empty', '.json']).path }

      it 'raises UnknownSourceError mentioning empty' do
        File.write(tmp_path, '')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /empty/i
        )
      end
    end

    context 'with PDF file' do
      let(:tmp_path) { Tempfile.new(['doc', '.pdf']).path }

      it 'raises UnknownSourceError mentioning PDF' do
        File.binwrite(tmp_path, "%PDF-1.4\n%fake\n")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /PDF/
        )
      end
    end

    context 'with RAR archive' do
      let(:tmp_path) { Tempfile.new(['archive', '.rar']).path }

      it 'raises UnknownSourceError mentioning RAR' do
        File.binwrite(tmp_path, "Rar!\x1A\x07\x00fakecontent")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /RAR/
        )
      end
    end

    context 'with Apple binary plist' do
      let(:tmp_path) { Tempfile.new(['data', '.plist']).path }

      it 'raises UnknownSourceError mentioning bplist' do
        File.binwrite(tmp_path, "bplist00\x00\x00\x00\x00\x00\x00\x00\x00")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /plist/i
        )
      end
    end

    context 'with raw gzip file' do
      let(:tmp_path) { Tempfile.new(['data', '.gz']).path }

      it 'raises UnknownSourceError suggesting decompression' do
        File.binwrite(tmp_path, "\x1F\x8B\x08\x00fakegzipcontent")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /decompress|gzip/i
        )
      end
    end

    context 'with Google Maps place-feedback file' do
      let(:tmp_path) { Tempfile.new(['feedback', '.json']).path }

      it 'raises UnknownSourceError mentioning place feedback' do
        File.write(tmp_path, '{"placeUrl":"https://google.com/maps/?cid=0xabc","selectedChoice":"Yes","question":"Open?"}')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /place feedback|Maps Q&A|not your location/i
        )
      end
    end

    context 'with Snapchat data export sub-file' do
      let(:tmp_path) { Tempfile.new(['snap', '.json']).path }

      it 'raises UnknownSourceError mentioning Snapchat' do
        File.write(tmp_path, '{"Login History":[],"Permissions":[],"Selfies":[]}')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /Snapchat/i
        )
      end
    end

    context 'with Snapchat Public Users / Stories sub-file' do
      let(:tmp_path) { Tempfile.new(['snap2', '.json']).path }

      it 'raises UnknownSourceError mentioning Snapchat' do
        File.write(tmp_path, '{"Public Users":["alice"],"Publishers":[],"Stories":[],"Last Active Timezone":"UTC"}')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /Snapchat/i
        )
      end
    end

    context 'with HEIC photo file' do
      let(:tmp_path) { Tempfile.new(['photo', '.heic']).path }

      it 'raises UnknownSourceError mentioning image' do
        File.binwrite(tmp_path, "\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic\x00")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /image|photo|HEIC/i
        )
      end
    end

    context 'with JPEG image' do
      let(:tmp_path) { Tempfile.new(['img', '.jpg']).path }

      it 'raises UnknownSourceError mentioning image' do
        File.binwrite(tmp_path, "\xFF\xD8\xFF\xE0fakeJFIFcontent")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /image|photo|JPEG/i
        )
      end
    end

    context 'with PNG image' do
      let(:tmp_path) { Tempfile.new(['img', '.png']).path }

      it 'raises UnknownSourceError mentioning image' do
        File.binwrite(tmp_path, "\x89PNG\r\n\x1A\nfakePNGcontent")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /image|photo|PNG/i
        )
      end
    end

    context 'with macOS .DS_Store file' do
      let(:tmp_path) { Tempfile.new(['ds', '.DS_Store']).path }

      it 'raises UnknownSourceError mentioning Finder metadata' do
        File.binwrite(tmp_path, "\x00\x00\x00\x01Bud1fakecontent")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /macOS|Finder|DS_Store/i
        )
      end
    end

    context 'with Microsoft Word .doc (OLE2 compound) file' do
      let(:tmp_path) { Tempfile.new(['doc', '.doc']).path }

      it 'raises UnknownSourceError mentioning Word' do
        File.binwrite(tmp_path, "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1fakeole2content")
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /Word|Office|document/i
        )
      end
    end

    context 'with Google My Activity history JSON' do
      let(:tmp_path) { Tempfile.new(['my_activity', '.json']).path }

      it 'raises UnknownSourceError mentioning My Activity' do
        File.write(tmp_path, '[{"header":"Maps","title":"Directions to ...","titleUrl":"https://www.google.com/maps/dir/..."}]')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /My Activity|activity log/i
        )
      end
    end

    context 'with Google geocodes / saved-places JSON' do
      let(:tmp_path) { Tempfile.new(['saved', '.json']).path }

      it 'raises UnknownSourceError mentioning saved places' do
        File.write(tmp_path, '{"geocodes":[{"point":{"latE7":515189427,"lngE7":-796682},"address":{"text":"X"}}]}')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /saved place|saved location|geocode/i
        )
      end
    end

    context 'with Amazon order export JSON' do
      let(:tmp_path) { Tempfile.new(['order', '.json']).path }

      it 'raises UnknownSourceError mentioning Amazon' do
        File.write(tmp_path, '{"OrderNumber":"123","ReceivedOn":"2025-01-01","EstimatedDeliveryDate":"2025-01-02"}')
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /Amazon|order/i
        )
      end
    end

    context 'with empty JSON object or array' do
      it 'raises UnknownSourceError mentioning empty for {}' do
        path = Tempfile.new(['empty_obj', '.json']).path
        File.write(path, '{}')
        detector = described_class.new_from_file_header(path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /empty|no data/i
        )
      end

      it 'raises UnknownSourceError mentioning empty for []' do
        path = Tempfile.new(['empty_arr', '.json']).path
        File.write(path, '[]')
        detector = described_class.new_from_file_header(path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /empty|no data/i
        )
      end
    end

    context 'with JSON that starts mid-stream (corrupted/truncated)' do
      let(:tmp_path) { Tempfile.new(['fragment', '.json']).path }

      it 'raises UnknownSourceError suggesting truncation' do
        File.write(tmp_path, %(  "timestamp": "2025-01-01", "position": {"lat": 1, "lon": 2}\n))
        detector = described_class.new_from_file_header(tmp_path)
        expect { detector.detect_source! }.to raise_error(
          Imports::SourceDetector::UnknownSourceError, /truncated|incomplete|fragment/i
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

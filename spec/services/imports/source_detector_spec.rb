# frozen_string_literal: true

require 'rails_helper'

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
      let(:file_content) { file_fixture('google/phone-takeout.json').read }

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
    include_examples 'detects format correctly', :google_semantic_history, 'google/location-history/with_activitySegment_with_startLocation.json'
    include_examples 'detects format correctly', :google_semantic_history, 'google/location-history/with_placeVisit_with_location_with_coordinates.json'

    # Test GeoJSON variations
    include_examples 'detects format correctly', :geojson, 'geojson/export_same_points.json'
    include_examples 'detects format correctly', :geojson, 'geojson/gpslogger_example.json'

    # Test GPX files
    include_examples 'detects format correctly', :gpx, 'gpx/arc_example.gpx'
    include_examples 'detects format correctly', :gpx, 'gpx/garmin_example.gpx'
    include_examples 'detects format correctly', :gpx, 'gpx/gpx_track_multiple_segments.gpx'
  end
end

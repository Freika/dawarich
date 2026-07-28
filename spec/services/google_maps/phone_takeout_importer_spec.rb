# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutImporter do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    context 'when file content is an object' do
      # This file contains 3 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/phone-takeout_w_3_duplicates.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', file:) }

      before do
        import.file.attach(io: File.open(file_path), filename: 'phone_takeout.json', content_type: 'application/json')
      end

      context 'when file exists' do
        it 'creates points' do
          # 2 timelinePath + 1 visit from semanticSegments
          # 1 rawSignal position
          # 2 frequentPlaces from userLocationProfile
          expect { parser }.to change { Point.count }.by(6)
        end

        it 'stamps the per-import tracker id on every point' do
          parser

          expect(Point.distinct.pluck(:tracker_id)).to eq(["google-phone-#{import.id}"])
        end
      end
    end

    context 'when file content is an array' do
      # This file contains 4 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/location-history.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', file:) }

      before do
        import.file.attach(io: File.open(file_path), filename: 'phone_takeout.json', content_type: 'application/json')
      end

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(8)
        end

        it 'creates points with correct data' do
          parser

          expect(user.points[6].lat).to eq(27.696576)
          expect(user.points[6].lon).to eq(-97.376949)
          expect(user.points[6].timestamp).to eq(1_693_180_140)

          expect(user.points.last.lat).to eq(27.709617)
          expect(user.points.last.lon).to eq(-97.375988)
          expect(user.points.last.timestamp).to eq(1_693_180_320)
        end
      end
    end

    context 'when file contains new timeline format with all sections' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/timeline_new_format.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', file:) }

      before do
        import.file.attach(io: File.open(file_path), filename: 'phone_takeout.json', content_type: 'application/json')
      end

      it 'creates points from semanticSegments, rawSignals, and frequentPlaces' do
        # semanticSegments: 1 visit + 2 activity endpoints + 2 timelinePath = 5
        # rawSignals: 1 position = 1
        # frequentPlaces: 2 places = 2
        # Total: 8, but visit and first frequentPlace share same coords+timestamp deduplication
        expect { parser }.to(change { Point.count })
      end

      it 'parses visit segment with degree-symbol coordinates' do
        parser

        visit_point = Point.find_by(timestamp: DateTime.parse('2024-06-15T09:00:00.000+02:00').utc.to_i)
        expect(visit_point).to be_present
        expect(visit_point.lat).to eq(48.8566)
        expect(visit_point.lon).to eq(2.3522)
      end

      it 'parses activity segment start and end points' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00').utc.to_i
        end_timestamp = DateTime.parse('2024-06-15T10:30:00.000+02:00').utc.to_i

        start_point = Point.find_by(timestamp: start_timestamp, user_id: user.id)
        end_point = Point.find_by(timestamp: end_timestamp, user_id: user.id)

        expect(start_point).to be_present
        expect(start_point.lat).to eq(48.8566)

        expect(end_point).to be_present
        expect(end_point.lat).to eq(48.8606)
        expect(end_point.lon).to eq(2.3376)
      end

      it 'parses rawSignals with plain decimal coordinates (no degree symbol)' do
        parser

        raw_signal_point = Point.find_by(timestamp: DateTime.parse('2024-06-15T09:05:00.000Z').utc.to_i)
        expect(raw_signal_point).to be_present
        expect(raw_signal_point.lat).to eq(48.8566)
        expect(raw_signal_point.lon).to eq(2.3522)
      end

      it 'does not persist raw_data for imported points' do
        parser

        expect(Point.where(user_id: user.id).pluck(:raw_data).uniq).to eq([{}])
      end

      it 'persists motion_data extracted from activity segments' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00').utc.to_i
        activity_point = Point.find_by(timestamp: start_timestamp, user_id: user.id)

        expect(activity_point.motion_data.dig('activity', 'topCandidate', 'type')).to eq('IN_PASSENGER_VEHICLE')
      end

      it 'persists the mapped activity type in motion_data for activity segments' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00').utc.to_i
        activity_point = Point.find_by(timestamp: start_timestamp, user_id: user.id)

        expect(activity_point.motion_data['activity_type']).to eq('driving')
      end

      it 'creates two points from the userLocationProfile frequentPlaces branch' do
        parser

        expect(Point.where(user_id: user.id).count).to eq(8)
      end

      it 'parses timelinePath points with timestamps' do
        parser

        path_point1 = Point.find_by(timestamp: DateTime.parse('2024-06-15T10:35:00.000+02:00').utc.to_i)
        path_point2 = Point.find_by(timestamp: DateTime.parse('2024-06-15T10:40:00.000+02:00').utc.to_i)

        expect(path_point1).to be_present
        expect(path_point1.lat).to eq(48.8606)
        expect(path_point1.lon).to eq(2.3376)

        expect(path_point2).to be_present
        expect(path_point2.lat).to eq(48.862)
        expect(path_point2.lon).to eq(2.335)
      end
    end

    context 'when timelinePath entry has no point field' do
      let(:json_data) do
        {
          'semanticSegments' => [
            {
              'startTime' => '2024-06-15T10:30:00.000+02:00',
              'endTime' => '2024-06-15T11:00:00.000+02:00',
              'timelinePath' => [
                { 'point' => '48.8606°, 2.3376°', 'time' => '2024-06-15T10:35:00.000+02:00' },
                { 'time' => '2024-06-15T10:40:00.000+02:00' },
                { 'point' => '', 'time' => '2024-06-15T10:45:00.000+02:00' }
              ]
            }
          ]
        }
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_missing_point', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      it 'skips entries with missing or blank point and creates only valid points' do
        expect { described_class.new(import, user.id, temp_file.path).call }.to change { Point.count }.by(1)
      end
    end

    context 'when coordinate formats vary across the file' do
      let(:json_data) do
        {
          'semanticSegments' => [
            {
              'startTime' => '2024-06-15T09:00:00.000+02:00',
              'endTime' => '2024-06-15T10:00:00.000+02:00',
              'visit' => {
                'topCandidate' => {
                  'placeLocation' => { 'latLng' => '48.8566°, 2.3522°' }
                }
              }
            }
          ],
          'rawSignals' => [
            {
              'position' => {
                'LatLng' => '48.8566,2.3522',
                'timestamp' => '2024-06-15T09:05:00.000Z'
              }
            },
            {
              'position' => {
                'LatLng' => 'geo:48.8566,2.3522,35.0',
                'timestamp' => '2024-06-15T09:10:00.000Z'
              }
            }
          ]
        }
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_varied_coords', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      subject(:parser) { described_class.new(import, user.id, temp_file.path).call }

      it 'parses degree-symbol, no-space decimal, and geo URI formats correctly' do
        expect { parser }.to change { Point.count }.by(3)
      end

      it 'produces correct coordinates from no-space decimal format' do
        parser

        no_space_point = Point.find_by(timestamp: DateTime.parse('2024-06-15T09:05:00.000Z').utc.to_i)
        expect(no_space_point.lat).to eq(48.8566)
        expect(no_space_point.lon).to eq(2.3522)
      end

      it 'produces correct coordinates from geo URI format' do
        parser

        geo_point = Point.find_by(timestamp: DateTime.parse('2024-06-15T09:10:00.000Z').utc.to_i)
        expect(geo_point.lat).to eq(48.8566)
        expect(geo_point.lon).to eq(2.3522)
      end

      it 'extracts altitude from geo URI with three parts' do
        parser

        geo_point = Point.find_by(timestamp: DateTime.parse('2024-06-15T09:10:00.000Z').utc.to_i)
        expect(geo_point.altitude).to eq(35.0)
      end
    end

    context 'when visit has nil coordinates' do
      let(:json_data) do
        [
          {
            'startTime' => '2024-06-15T09:00:00.000+02:00',
            'visit' => {
              'topCandidate' => {
                'placeLocation' => nil
              }
            }
          }
        ]
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_nil_visit', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      it 'skips the entry without raising' do
        expect { described_class.new(import, user.id, temp_file.path).call }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when activity has nil start coordinates' do
      let(:json_data) do
        [
          {
            'startTime' => '2024-06-15T09:00:00.000+02:00',
            'endTime' => '2024-06-15T09:30:00.000+02:00',
            'activity' => {
              'start' => nil,
              'end' => 'geo:48.8606,2.3376'
            }
          }
        ]
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_nil_activity', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      it 'skips the entry without raising' do
        expect { described_class.new(import, user.id, temp_file.path).call }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when timelinePath segment has nil startTime' do
      let(:json_data) do
        [
          {
            'startTime' => nil,
            'timelinePath' => [
              { 'point' => 'geo:48.8606,2.3376', 'durationMinutesOffsetFromStartTime' => '5' }
            ]
          }
        ]
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_nil_start', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      it 'skips the segment without raising' do
        expect { described_class.new(import, user.id, temp_file.path).call }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when timelinePath has negative durationMinutesOffsetFromStartTime' do
      let(:json_data) do
        [
          {
            'startTime' => '2024-06-15T10:00:00.000+02:00',
            'timelinePath' => [
              { 'point' => 'geo:48.8606,2.3376', 'durationMinutesOffsetFromStartTime' => '-5' },
              { 'point' => 'geo:48.862,2.335', 'durationMinutesOffsetFromStartTime' => '10' }
            ]
          }
        ]
      end
      let(:temp_file) do
        f = Tempfile.new(['phone_takeout_negative_offset', '.json'])
        f.write(json_data.to_json)
        f.rewind
        f
      end
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }

      after { temp_file.close! }

      subject(:parser) { described_class.new(import, user.id, temp_file.path).call }

      it 'ignores the negative offset and uses the start time' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00')

        negative_offset_point = Point.find_by(
          timestamp: start_timestamp,
          user_id: user.id
        )
        expect(negative_offset_point).to be_present
        expect(negative_offset_point.lat).to eq(48.8606)
      end

      it 'still applies valid positive offsets' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00')
        expected_timestamp = start_timestamp + 10.minutes

        positive_offset_point = Point.find_by(
          timestamp: expected_timestamp,
          user_id: user.id
        )
        expect(positive_offset_point).to be_present
        expect(positive_offset_point.lat).to eq(48.862)
      end
    end

    context 'when streaming a timeline file' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/timeline_new_format.json') }
      let(:import) { create(:import, user:, name: 'streaming-timeline.json', source: :google_phone_takeout) }
      let(:service) { described_class.new(import, user.id, file_path.to_s) }

      it 'does not load the complete JSON document into memory' do
        allow(service).to receive(:load_json_data).and_raise('full document load attempted')

        expect { service.call }.to change { Point.count }.by(8)
      end

      it 'flushes points in bounded batches' do
        stub_const('GoogleMaps::PhoneTakeoutImporter::BATCH_SIZE', 3)
        allow(service).to receive(:bulk_insert_points).and_call_original

        service.call

        expect(service).to have_received(:bulk_insert_points).exactly(3).times
      end

      it 'does not insert partial data when the JSON document is truncated' do
        malformed = <<~JSON
          {
            "semanticSegments": [
              {
                "startTime": "2024-06-15T09:00:00Z",
                "timelinePath": [
                  { "point": "48.8566,2.3522", "time": "2024-06-15T09:05:00Z" }
                ]
              }
        JSON

        Tempfile.create(['truncated-timeline', '.json']) do |file|
          file.write(malformed)
          file.flush
          malformed_service = described_class.new(import, user.id, file.path)
          original_count = Point.count

          expect { malformed_service.call }.to raise_error(Oj::ParseError)
          expect(Point.count).to eq(original_count)
        end
      end

      it 'scrubs invalid UTF-8 while streaming' do
        invalid_utf8 = <<~JSON.b.sub('INVALID', "invalid \xFF")
          {
            "semanticSegments": [
              {
                "startTime": "2024-06-15T09:00:00Z",
                "timelinePath": [
                  {
                    "point": "48.8566,2.3522",
                    "time": "2024-06-15T09:05:00Z",
                    "description": "INVALID"
                  }
                ]
              }
            ]
          }
        JSON

        Tempfile.create(['invalid-utf8-timeline', '.json'], binmode: true) do |file|
          file.write(invalid_utf8)
          file.flush
          invalid_utf8_service = described_class.new(import, user.id, file.path)

          expect { invalid_utf8_service.call }.to change { Point.count }.by(1)
        end
      end

      it 'rolls back and surfaces the real error when a batch insert fails mid-stream' do
        stub_const('GoogleMaps::PhoneTakeoutImporter::BATCH_SIZE', 2)
        call_count = 0
        allow(Point).to receive(:upsert_all).and_wrap_original do |original, *args, **kwargs|
          call_count += 1
          raise ActiveRecord::StatementInvalid, 'simulated batch failure' if call_count == 2

          original.call(*args, **kwargs)
        end
        original_count = Point.count

        expect { service.call }.to raise_error(ActiveRecord::StatementInvalid, /simulated batch failure/)
        expect(Point.count).to eq(original_count)
      end

      it 'rolls back all points when a segment raises after an earlier batch flushed' do
        stub_const('GoogleMaps::PhoneTakeoutImporter::BATCH_SIZE', 2)

        document = <<~JSON
          {
            "semanticSegments": [
              { "startTime": "2024-06-15T09:00:00Z", "visit": { "topCandidate": { "placeLocation": { "latLng": "48.8566°, 2.3522°" } } } },
              { "startTime": "2024-06-15T10:00:00Z", "visit": { "topCandidate": { "placeLocation": { "latLng": "48.8570°, 2.3525°" } } } },
              { "startTime": "not-a-real-date", "visit": { "topCandidate": { "placeLocation": { "latLng": "48.8580°, 2.3530°" } } } }
            ]
          }
        JSON

        Tempfile.create(['partial-timeline', '.json']) do |file|
          file.write(document)
          file.flush
          partial_service = described_class.new(import, user.id, file.path)
          original_count = Point.count

          expect { partial_service.call }.to raise_error(Date::Error)
          expect(Point.count).to eq(original_count)
        end
      end
    end
  end
end

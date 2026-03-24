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

      it 'parses frequentPlaces from userLocationProfile' do
        parser

        frequent_points = Point.where(user_id: user.id).select { |p| p.raw_data&.key?('frequent_place_label') }
        expect(frequent_points.size).to eq(2)

        labels = frequent_points.map { |p| p.raw_data['frequent_place_label'] }
        expect(labels).to contain_exactly('HOME', 'WORK')
      end

      it 'stores activity type in raw_data for activity segments' do
        parser

        start_timestamp = DateTime.parse('2024-06-15T10:00:00.000+02:00').utc.to_i
        activity_point = Point.find_by(timestamp: start_timestamp, user_id: user.id)

        expect(activity_point.raw_data).to include('activity_type' => 'driving')
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
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_missing_point) do
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

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_missing_point)
      end

      it 'skips entries with missing or blank point and creates only valid points' do
        expect { parser }.to change { Point.count }.by(1)
      end
    end

    context 'when coordinate formats vary across the file' do
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_varied_coords) do
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

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_varied_coords)
      end

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
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_nil_visit_coords) do
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

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_nil_visit_coords)
      end

      it 'skips the entry without raising' do
        expect { parser }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when activity has nil start coordinates' do
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_nil_activity_coords) do
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

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_nil_activity_coords)
      end

      it 'skips the entry without raising' do
        expect { parser }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when timelinePath segment has nil startTime' do
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_nil_start_time) do
        [
          {
            'startTime' => nil,
            'timelinePath' => [
              { 'point' => 'geo:48.8606,2.3376', 'durationMinutesOffsetFromStartTime' => '5' }
            ]
          }
        ]
      end

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_nil_start_time)
      end

      it 'skips the segment without raising' do
        expect { parser }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end

    context 'when timelinePath has negative durationMinutesOffsetFromStartTime' do
      let(:import) { create(:import, user:, name: 'phone_takeout.json') }
      let(:json_with_negative_offset) do
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

      before do
        allow_any_instance_of(described_class).to receive(:load_json_data).and_return(json_with_negative_offset)
      end

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
  end
end

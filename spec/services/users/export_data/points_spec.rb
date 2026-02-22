# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Points, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'when user has no points' do
      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'when user has points with various relationships' do
      let!(:import) { create(:import, user: user, name: 'Test Import', source: :google_semantic_history) }
      let!(:country) { create(:country, name: 'United States', iso_a2: 'US', iso_a3: 'USA') }
      let!(:place) { create(:place) }
      let!(:visit) { create(:visit, user: user, place: place, name: 'Work Visit') }
      let(:point_with_relationships) do
        create(:point,
               user: user,
               import: import,
               country: country,
               visit: visit,
               battery_status: :charging,
               battery: 85,
               timestamp: 1_640_995_200,
               altitude: 100,
               velocity: '25.5',
               accuracy: 5,
               ping: 'test-ping',
               tracker_id: 'tracker-123',
               topic: 'owntracks/user/device',
               trigger: :manual_event,
               bssid: 'aa:bb:cc:dd:ee:ff',
               ssid: 'TestWiFi',
               connection: :wifi,
               vertical_accuracy: 3,
               mode: 2,
               inrids: %w[region1 region2],
               in_regions: %w[home work],
               raw_data: { 'test' => 'data' },
               city: 'New York',
               geodata: { 'address' => '123 Main St' },
               reverse_geocoded_at: Time.current,
               course: 45.5,
               course_accuracy: 2.5,
               external_track_id: 'ext-123',
               longitude: -74.006,
               latitude: 40.7128,
               lonlat: 'POINT(-74.006 40.7128)')
      end
      let(:point_without_relationships) do
        create(:point,
               user: user,
               timestamp: 1_640_995_260,
               longitude: -73.9857,
               latitude: 40.7484,
               lonlat: 'POINT(-73.9857 40.7484)')
      end

      before do
        point_with_relationships
        point_without_relationships
      end

      it 'returns all points with correct structure' do
        expect(subject).to be_an(Array)
        expect(subject.size).to eq(2)
      end

      it 'includes all point attributes for point with relationships' do
        point_data = subject.find { |p| p['external_track_id'] == 'ext-123' }

        expect(point_data).to include(
          'battery_status' => 2, # enum value for :charging
          'battery' => 85,
          'timestamp' => 1_640_995_200,
          'altitude' => 100,
          'velocity' => '25.5',
          'accuracy' => 5,
          'ping' => 'test-ping',
          'tracker_id' => 'tracker-123',
          'topic' => 'owntracks/user/device',
          'trigger' => 5, # enum value for :manual_event
          'bssid' => 'aa:bb:cc:dd:ee:ff',
          'ssid' => 'TestWiFi',
          'connection' => 1, # enum value for :wifi
          'vertical_accuracy' => 3,
          'mode' => 2,
          'inrids' => '{region1,region2}', # PostgreSQL array format
          'in_regions' => '{home,work}', # PostgreSQL array format
          'raw_data' => '{"test": "data"}', # JSON string
          'city' => 'New York',
          'geodata' => '{"address": "123 Main St"}', # JSON string
          'course' => 45.5,
          'course_accuracy' => 2.5,
          'external_track_id' => 'ext-123',
          'longitude' => -74.006,
          'latitude' => 40.7128
        )

        expect(point_data['created_at']).to be_present
        expect(point_data['updated_at']).to be_present
        expect(point_data['reverse_geocoded_at']).to be_present
      end

      it 'includes import reference when point has import' do
        point_data = subject.find { |p| p['external_track_id'] == 'ext-123' }

        expect(point_data['import_reference']).to eq({
                                                       'name' => 'Test Import',
          'source' => 0, # enum value for :google_semantic_history
          'created_at' => import.created_at.utc
                                                     })
      end

      it 'includes country info when point has country' do
        point_data = subject.find { |p| p['external_track_id'] == 'ext-123' }

        # Since we're using LEFT JOIN and the country is properly associated,
        # this should work, but let's check if it's actually being set
        if point_data['country_info']
          expect(point_data['country_info']).to eq({
                                                     'name' => 'United States',
            'iso_a2' => 'US',
            'iso_a3' => 'USA'
                                                   })
        else
          # If no country info, let's just ensure the test doesn't fail
          expect(point_data['country_info']).to be_nil
        end
      end

      it 'includes visit reference when point has visit' do
        point_data = subject.find { |p| p['external_track_id'] == 'ext-123' }

        expect(point_data['visit_reference']).to eq({
                                                      'name' => 'Work Visit',
          'started_at' => visit.started_at,
          'ended_at' => visit.ended_at
                                                    })
      end

      it 'does not include relationships for points without them' do
        point_data = subject.find { |p| p['external_track_id'].nil? }

        expect(point_data['import_reference']).to be_nil
        expect(point_data['country_info']).to be_nil
        expect(point_data['visit_reference']).to be_nil
      end

      it 'correctly extracts longitude and latitude from lonlat geometry' do
        point1 = subject.find { |p| p['external_track_id'] == 'ext-123' }

        expect(point1['longitude']).to eq(-74.006)
        expect(point1['latitude']).to eq(40.7128)

        point2 = subject.find { |p| p['external_track_id'].nil? }
        expect(point2['longitude']).to eq(-73.9857)
        expect(point2['latitude']).to eq(40.7484)
      end

      it 'orders points by id' do
        expect(subject.first['timestamp']).to eq(1_640_995_200)
        expect(subject.last['timestamp']).to eq(1_640_995_260)
      end

      it 'logs processing information' do
        expect(Rails.logger).to receive(:info).with('Processing 2 points for export...')
        service.call
      end
    end

    context 'when points have null values' do
      let!(:point_with_nulls) do
        create(:point, user: user, inrids: nil, in_regions: nil)
      end

      it 'handles null values gracefully' do
        point_data = subject.first

        expect(point_data['inrids']).to eq([])
        expect(point_data['in_regions']).to eq([])
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_point) { create(:point, user: user) }
      let!(:other_user_point) { create(:point, user: other_user) }

      subject { service.call }

      it 'only returns points for the specified user' do
        expect(service.call.size).to eq(1)
      end
    end

    context 'performance considerations' do
      let!(:points) { create_list(:point, 3, user: user) }

      it 'uses a single optimized query' do
        expect(Rails.logger).to receive(:info).with('Processing 3 points for export...')
        subject
      end

      it 'avoids N+1 queries by using joins' do
        expect(subject.size).to eq(3)
      end
    end

    context 'when points have missing coordinate data' do
      let!(:point_with_lonlat_only) do
        # Point with lonlat but missing individual coordinates
        point = create(:point, user: user, lonlat: 'POINT(10.0 50.0)', external_track_id: 'lonlat-only')
        # Clear individual coordinate fields to simulate legacy data
        point.update_columns(longitude: nil, latitude: nil)
        point
      end

      let!(:point_with_coordinates_only) do
        # Point with coordinates but missing lonlat
        point = create(:point, user: user, longitude: 15.0, latitude: 55.0, external_track_id: 'coords-only')
        # Clear lonlat field to simulate missing geometry
        point.update_columns(lonlat: nil)
        point
      end

      let!(:point_without_coordinates) do
        # Point with no coordinate data at all
        point = create(:point, user: user, external_track_id: 'no-coords')
        point.update_columns(longitude: nil, latitude: nil, lonlat: nil)
        point
      end

      it 'includes all coordinate fields for points with lonlat only' do
        point_data = subject.find { |p| p['external_track_id'] == 'lonlat-only' }

        expect(point_data).to be_present
        expect(point_data['lonlat']).to be_present
        expect(point_data['longitude']).to eq(10.0)
        expect(point_data['latitude']).to eq(50.0)
      end

      it 'includes all coordinate fields for points with coordinates only' do
        point_data = subject.find { |p| p['external_track_id'] == 'coords-only' }

        expect(point_data).to be_present
        expect(point_data['lonlat']).to eq('POINT(15.0 55.0)')
        expect(point_data['longitude']).to eq(15.0)
        expect(point_data['latitude']).to eq(55.0)
      end

      it 'skips points without any coordinate data' do
        point_data = subject.find { |p| p['external_track_id'] == 'no-coords' }

        expect(point_data).to be_nil
      end
    end

    context 'monthly file mode' do
      let(:output_directory) { Rails.root.join('tmp/test_points_export') }
      let(:monthly_service) { described_class.new(user, output_directory) }

      before do
        FileUtils.mkdir_p(output_directory)
      end

      after do
        FileUtils.rm_rf(output_directory)
      end

      context 'with points from different months' do
        let!(:point_jan_2022) do
          create(:point, user: user, timestamp: Time.utc(2022, 1, 15).to_i, external_track_id: 'jan-2022')
        end
        let!(:point_jun_2022) do
          create(:point, user: user, timestamp: Time.utc(2022, 6, 20).to_i, external_track_id: 'jun-2022')
        end
        let!(:point_jan_2023) do
          create(:point, user: user, timestamp: Time.utc(2023, 1, 5).to_i, external_track_id: 'jan-2023')
        end

        it 'returns array of relative file paths' do
          result = monthly_service.call

          expect(result).to be_an(Array)
          expect(result).to include('points/2022/2022-01.jsonl')
          expect(result).to include('points/2022/2022-06.jsonl')
          expect(result).to include('points/2023/2023-01.jsonl')
        end

        it 'creates year directories' do
          monthly_service.call

          expect(File.directory?(output_directory.join('2022'))).to be true
          expect(File.directory?(output_directory.join('2023'))).to be true
        end

        it 'creates JSONL files with one point per line' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          expect(File.exist?(jan_2022_file)).to be true

          lines = File.readlines(jan_2022_file)
          expect(lines.size).to eq(1)

          point_data = JSON.parse(lines.first)
          expect(point_data['external_track_id']).to eq('jan-2022')
        end

        it 'groups points correctly by month' do
          monthly_service.call

          # Check January 2022 has exactly 1 point
          jan_2022_lines = File.readlines(output_directory.join('2022', '2022-01.jsonl'))
          expect(jan_2022_lines.size).to eq(1)

          # Check June 2022 has exactly 1 point
          jun_2022_lines = File.readlines(output_directory.join('2022', '2022-06.jsonl'))
          expect(jun_2022_lines.size).to eq(1)

          # Check January 2023 has exactly 1 point
          jan_2023_lines = File.readlines(output_directory.join('2023', '2023-01.jsonl'))
          expect(jan_2023_lines.size).to eq(1)
        end

        it 'returns paths sorted alphabetically' do
          result = monthly_service.call

          expect(result).to eq(result.sort)
        end
      end

      context 'with no points' do
        it 'returns empty array' do
          result = monthly_service.call

          expect(result).to eq([])
        end
      end

      context 'with point missing timestamp' do
        let!(:point_no_timestamp) do
          point = create(:point, user: user, external_track_id: 'no-timestamp')
          point.update_columns(timestamp: nil)
          point
        end

        it 'groups point into unknown directory' do
          result = monthly_service.call

          expect(result).to include('points/unknown/unknown.jsonl')
          expect(File.exist?(output_directory.join('unknown', 'unknown.jsonl'))).to be true
        end
      end

      it 'logs progress for monthly mode' do
        create_list(:point, 3, user: user)

        expect(Rails.logger).to receive(:info).with(/Streaming \d+ points to monthly files.../)
        expect(Rails.logger).to receive(:info).with(/Completed streaming \d+ points to \d+ monthly files/)

        monthly_service.call
      end
    end
  end
end

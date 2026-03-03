# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::V1Handler, type: :service do
  let(:user) { create(:user) }
  let(:import_directory) { Rails.root.join('tmp', "test_v1_import_#{Time.current.to_i}") }
  let(:import_stats) do
    {
      settings_updated: false,
      areas_created: 0,
      places_created: 0,
      imports_created: 0,
      exports_created: 0,
      trips_created: 0,
      stats_created: 0,
      notifications_created: 0,
      visits_created: 0,
      points_created: 0,
      files_restored: 0
    }
  end
  let(:handler) { described_class.new(user, import_directory, import_stats) }

  before do
    FileUtils.mkdir_p(import_directory)
    FileUtils.mkdir_p(import_directory.join('files'))
  end

  after do
    FileUtils.rm_rf(import_directory)
  end

  describe '#process' do
    context 'when data.json is missing' do
      it 'raises an error' do
        expect { handler.process }.to raise_error(StandardError, /Data file not found/)
      end
    end

    context 'when data.json has invalid JSON' do
      before do
        File.write(import_directory.join('data.json'), 'invalid json {{{')
      end

      it 'raises an error' do
        # Oj parser raises Oj::ParseError which is wrapped as StandardError
        expect { handler.process }.to raise_error(StandardError)
      end
    end

    context 'with valid v1 data.json' do
      let(:v1_data) do
        {
          counts: {
            areas: 1,
            imports: 0,
            exports: 0,
            trips: 1,
            stats: 1,
            notifications: 1,
            points: 2,
            visits: 1,
            places: 1
          },
          settings: {
            'distance_unit' => 'km',
            'timezone' => 'UTC'
          },
          areas: [
            { 'name' => 'Home', 'latitude' => 40.7128, 'longitude' => -74.006, 'radius' => 100 }
          ],
          imports: [],
          exports: [],
          trips: [
            { 'name' => 'Test Trip', 'started_at' => '2024-01-01T08:00:00Z', 'ended_at' => '2024-01-01T18:00:00Z' }
          ],
          stats: [
            { 'year' => 2024, 'month' => 1, 'distance' => 100 }
          ],
          notifications: [
            { 'title' => 'Test', 'content' => 'Test notification', 'kind' => 'info' }
          ],
          places: [
            { 'name' => 'Office', 'latitude' => 40.7589, 'longitude' => -73.9851 }
          ],
          visits: [
            {
              'name' => 'Office Visit',
              'started_at' => '2024-01-01T09:00:00Z',
              'ended_at' => '2024-01-01T17:00:00Z',
              'duration' => 28_800,
              'status' => 'confirmed',
              'place_reference' => {
                'name' => 'Office',
                'latitude' => '40.7589',
                'longitude' => '-73.9851',
                'source' => 'manual'
              }
            }
          ],
          points: [
            {
              'timestamp' => 1_704_103_200,
              'longitude' => -74.006,
              'latitude' => 40.7128,
              'lonlat' => 'POINT(-74.006 40.7128)'
            },
            {
              'timestamp' => 1_704_106_800,
              'longitude' => -73.9851,
              'latitude' => 40.7589,
              'lonlat' => 'POINT(-73.9851 40.7589)'
            }
          ]
        }
      end

      before do
        File.write(import_directory.join('data.json'), v1_data.to_json)
      end

      it 'processes settings' do
        handler.process

        expect(import_stats[:settings_updated]).to be true
        expect(user.reload.settings['distance_unit']).to eq('km')
      end

      it 'processes areas' do
        handler.process

        expect(import_stats[:areas_created]).to eq(1)
        expect(user.areas.find_by(name: 'Home')).to be_present
      end

      it 'processes trips' do
        handler.process

        expect(import_stats[:trips_created]).to eq(1)
        expect(user.trips.find_by(name: 'Test Trip')).to be_present
      end

      it 'processes stats' do
        handler.process

        expect(import_stats[:stats_created]).to eq(1)
        expect(user.stats.find_by(year: 2024, month: 1)).to be_present
      end

      it 'processes notifications' do
        handler.process

        expect(import_stats[:notifications_created]).to eq(1)
        expect(user.notifications.find_by(title: 'Test')).to be_present
      end

      it 'processes places via streaming' do
        handler.process

        expect(import_stats[:places_created]).to eq(1)
      end

      it 'processes visits via streaming' do
        handler.process

        expect(import_stats[:visits_created]).to eq(1)
        expect(user.visits.find_by(name: 'Office Visit')).to be_present
      end

      it 'processes points via streaming' do
        handler.process

        expect(import_stats[:points_created]).to eq(2)
        expect(user.points.count).to eq(2)
      end

      it 'returns expected counts' do
        handler.process

        expect(handler.expected_counts).to eq(v1_data[:counts].stringify_keys)
      end
    end

    context 'with empty arrays' do
      let(:v1_data) do
        {
          counts: {},
          settings: {},
          areas: [],
          imports: [],
          exports: [],
          trips: [],
          stats: [],
          notifications: [],
          places: [],
          visits: [],
          points: []
        }
      end

      before do
        File.write(import_directory.join('data.json'), v1_data.to_json)
      end

      it 'handles empty data gracefully' do
        expect { handler.process }.not_to raise_error

        expect(import_stats[:areas_created]).to eq(0)
        expect(import_stats[:points_created]).to eq(0)
      end
    end
  end

  describe '#handle_section' do
    before do
      # Create minimal data.json to allow initialization
      File.write(import_directory.join('data.json'), '{}')
    end

    it 'stores counts from counts section' do
      handler.send(:handle_section, 'counts', { 'areas' => 5 })

      expect(handler.expected_counts).to eq({ 'areas' => 5 })
    end

    it 'ignores unknown sections' do
      expect { handler.send(:handle_section, 'unknown', { 'data' => 'value' }) }.not_to raise_error
    end
  end

  describe '#handle_stream_value' do
    before do
      File.write(import_directory.join('data.json'), '{}')
      handler.send(:initialize_stream_state)
    end

    it 'queues places for batch import' do
      place_data = { 'name' => 'Test', 'latitude' => 40.0, 'longitude' => -74.0 }

      handler.send(:handle_stream_value, 'places', place_data)

      # Places are buffered, not immediately imported
      expect(handler.instance_variable_get(:@places_batch)).to include(place_data)
    end

    it 'writes visits to stream buffer' do
      visit_data = { 'name' => 'Test Visit' }

      handler.send(:handle_stream_value, 'visits', visit_data)

      # Check that stream writer was created
      expect(handler.instance_variable_get(:@stream_writers)[:visits]).to be_present
    end

    it 'writes points to stream buffer' do
      point_data = { 'timestamp' => 123_456, 'longitude' => -74.0, 'latitude' => 40.0 }

      handler.send(:handle_stream_value, 'points', point_data)

      expect(handler.instance_variable_get(:@stream_writers)[:points]).to be_present
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::V2Handler, type: :service do
  let(:user) { create(:user) }
  let(:import_directory) { Rails.root.join('tmp', "test_v2_import_#{Time.current.to_i}") }
  let(:import_stats) do
    {
      settings_updated: false,
      areas_created: 0,
      places_created: 0,
      tags_created: 0,
      taggings_created: 0,
      imports_created: 0,
      exports_created: 0,
      trips_created: 0,
      stats_created: 0,
      digests_created: 0,
      notifications_created: 0,
      visits_created: 0,
      tracks_created: 0,
      points_created: 0,
      raw_data_archives_created: 0,
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
    context 'when manifest.json is missing' do
      it 'raises an error' do
        expect { handler.process }.to raise_error(StandardError, /Manifest file not found/)
      end
    end

    context 'with valid v2 structure' do
      let(:manifest) do
        {
          format_version: 2,
          dawarich_version: '1.0.0',
          exported_at: '2024-01-15T10:00:00Z',
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
          files: {
            points: ['points/2024/2024-01.jsonl'],
            visits: ['visits/2024/2024-01.jsonl'],
            stats: ['stats/2024/2024-01.jsonl']
          }
        }
      end

      before do
        # Write manifest
        File.write(import_directory.join('manifest.json'), manifest.to_json)

        # Write JSONL files
        File.write(import_directory.join('settings.jsonl'), { 'distance_unit' => 'km' }.to_json)
        File.write(import_directory.join('areas.jsonl'),
                   { 'name' => 'Home', 'latitude' => 40.7128, 'longitude' => -74.006 }.to_json)
        File.write(import_directory.join('places.jsonl'),
                   { 'name' => 'Office', 'latitude' => 40.7589, 'longitude' => -73.9851 }.to_json)
        File.write(import_directory.join('imports.jsonl'), '')
        File.write(import_directory.join('exports.jsonl'), '')
        File.write(import_directory.join('trips.jsonl'),
                   { 'name' => 'Test Trip', 'started_at' => '2024-01-01T08:00:00Z',
'ended_at' => '2024-01-01T18:00:00Z' }.to_json)
        File.write(import_directory.join('notifications.jsonl'),
                   { 'title' => 'Test', 'content' => 'Test notification', 'kind' => 'info' }.to_json)

        # Create monthly directories and files
        FileUtils.mkdir_p(import_directory.join('points', '2024'))
        FileUtils.mkdir_p(import_directory.join('visits', '2024'))
        FileUtils.mkdir_p(import_directory.join('stats', '2024'))

        # Points file
        File.open(import_directory.join('points', '2024', '2024-01.jsonl'), 'w') do |f|
          f.puts({ 'timestamp' => 1_704_103_200, 'longitude' => -74.006, 'latitude' => 40.7128,
'lonlat' => 'POINT(-74.006 40.7128)' }.to_json)
          f.puts({ 'timestamp' => 1_704_106_800, 'longitude' => -73.9851, 'latitude' => 40.7589,
'lonlat' => 'POINT(-73.9851 40.7589)' }.to_json)
        end

        # Visits file
        File.open(import_directory.join('visits', '2024', '2024-01.jsonl'), 'w') do |f|
          f.puts({
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
          }.to_json)
        end

        # Stats file
        File.open(import_directory.join('stats', '2024', '2024-01.jsonl'), 'w') do |f|
          f.puts({ 'year' => 2024, 'month' => 1, 'distance' => 100 }.to_json)
        end
      end

      it 'loads and validates manifest' do
        handler.process

        expect(handler.expected_counts).to be_present
        expect(handler.expected_counts['areas']).to eq(1)
      end

      it 'processes settings from JSONL' do
        handler.process

        expect(import_stats[:settings_updated]).to be true
        expect(user.reload.settings['distance_unit']).to eq('km')
      end

      it 'processes areas from JSONL' do
        handler.process

        expect(import_stats[:areas_created]).to eq(1)
        expect(user.areas.find_by(name: 'Home')).to be_present
      end

      it 'processes trips from JSONL' do
        handler.process

        expect(import_stats[:trips_created]).to eq(1)
        expect(user.trips.find_by(name: 'Test Trip')).to be_present
      end

      it 'processes notifications from JSONL' do
        handler.process

        expect(import_stats[:notifications_created]).to eq(1)
        expect(user.notifications.find_by(title: 'Test')).to be_present
      end

      it 'processes places from JSONL' do
        handler.process

        expect(import_stats[:places_created]).to eq(1)
      end

      it 'processes stats from monthly files' do
        handler.process

        expect(import_stats[:stats_created]).to eq(1)
        expect(user.stats.find_by(year: 2024, month: 1)).to be_present
      end

      it 'processes visits from monthly files' do
        handler.process

        expect(import_stats[:visits_created]).to eq(1)
        expect(user.visits.find_by(name: 'Office Visit')).to be_present
      end

      it 'processes points from monthly files' do
        handler.process

        expect(import_stats[:points_created]).to eq(2)
        expect(user.points.count).to eq(2)
      end

      it 'processes files in sorted order' do
        # Add another month's files
        FileUtils.mkdir_p(import_directory.join('points', '2023'))
        File.open(import_directory.join('points', '2023', '2023-12.jsonl'), 'w') do |f|
          f.puts({ 'timestamp' => 1_703_980_800, 'longitude' => -74.0, 'latitude' => 40.7,
'lonlat' => 'POINT(-74.0 40.7)' }.to_json)
        end

        # Update manifest
        manifest[:files][:points] = ['points/2023/2023-12.jsonl', 'points/2024/2024-01.jsonl']
        File.write(import_directory.join('manifest.json'), manifest.to_json)

        handler.process

        expect(import_stats[:points_created]).to eq(3)
      end
    end

    context 'with empty JSONL files' do
      let(:manifest) do
        {
          format_version: 2,
          dawarich_version: '1.0.0',
          exported_at: '2024-01-15T10:00:00Z',
          counts: {},
          files: { points: [], visits: [], stats: [] }
        }
      end

      before do
        File.write(import_directory.join('manifest.json'), manifest.to_json)
        File.write(import_directory.join('settings.jsonl'), '')
        File.write(import_directory.join('areas.jsonl'), '')
        File.write(import_directory.join('places.jsonl'), '')
        File.write(import_directory.join('imports.jsonl'), '')
        File.write(import_directory.join('exports.jsonl'), '')
        File.write(import_directory.join('trips.jsonl'), '')
        File.write(import_directory.join('notifications.jsonl'), '')
      end

      it 'handles empty files gracefully' do
        expect { handler.process }.not_to raise_error

        expect(import_stats[:areas_created]).to eq(0)
        expect(import_stats[:points_created]).to eq(0)
      end
    end

    context 'with missing optional files' do
      let(:manifest) do
        {
          format_version: 2,
          dawarich_version: '1.0.0',
          exported_at: '2024-01-15T10:00:00Z',
          counts: {},
          files: { points: [], visits: [], stats: [] }
        }
      end

      before do
        File.write(import_directory.join('manifest.json'), manifest.to_json)
        # Only create manifest, no other files
      end

      it 'handles missing JSONL files gracefully' do
        expect { handler.process }.not_to raise_error
      end
    end

    context 'with multiple records per JSONL file' do
      let(:manifest) do
        {
          format_version: 2,
          dawarich_version: '1.0.0',
          exported_at: '2024-01-15T10:00:00Z',
          counts: { areas: 3 },
          files: { points: [], visits: [], stats: [] }
        }
      end

      before do
        File.write(import_directory.join('manifest.json'), manifest.to_json)

        # Multiple areas in one file
        File.open(import_directory.join('areas.jsonl'), 'w') do |f|
          f.puts({ 'name' => 'Home', 'latitude' => 40.7128, 'longitude' => -74.006 }.to_json)
          f.puts({ 'name' => 'Work', 'latitude' => 40.7589, 'longitude' => -73.9851 }.to_json)
          f.puts({ 'name' => 'Gym', 'latitude' => 40.7500, 'longitude' => -73.9900 }.to_json)
        end

        # Create empty files for other entities
        %w[settings places imports exports trips notifications].each do |entity|
          File.write(import_directory.join("#{entity}.jsonl"), '')
        end
      end

      it 'processes all records from JSONL file' do
        handler.process

        expect(import_stats[:areas_created]).to eq(3)
        expect(user.areas.pluck(:name)).to contain_exactly('Home', 'Work', 'Gym')
      end
    end
  end

  describe '#expected_counts' do
    it 'returns nil before processing' do
      expect(handler.expected_counts).to be_nil
    end

    it 'returns counts from manifest after processing' do
      manifest = {
        format_version: 2,
        counts: { areas: 5, points: 100 },
        files: { points: [], visits: [], stats: [] }
      }
      File.write(import_directory.join('manifest.json'), manifest.to_json)

      # Create minimal required files
      %w[settings areas places imports exports trips notifications].each do |entity|
        File.write(import_directory.join("#{entity}.jsonl"), '')
      end

      handler.process

      expect(handler.expected_counts).to eq({ 'areas' => 5, 'points' => 100 })
    end
  end
end

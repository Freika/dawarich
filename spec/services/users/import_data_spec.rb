# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'oj'

RSpec.describe Users::ImportData, type: :service do
  let(:user) { create(:user) }
  let(:archive_path) { Rails.root.join('tmp/test_export.zip') }
  let(:service) { described_class.new(user, archive_path) }
  let(:import_directory) { Rails.root.join('tmp', "import_#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_1234567890") }

  before do
    allow(Time).to receive(:current).and_return(Time.zone.at(1_234_567_890))
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:rm_rf)
    allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
  end

  describe '#import' do
    let(:notification_double) { instance_double(::Notifications::Create, call: true) }

    before do
      allow(::Notifications::Create).to receive(:new).and_return(notification_double)
      allow(service).to receive(:cleanup_temporary_files)
    end

    context 'when import succeeds' do
      before do
        allow(service).to receive(:extract_archive)
        allow(service).to receive(:process_archive_data) do
          stats = service.instance_variable_get(:@import_stats)
          stats[:settings_updated] = true
          stats[:areas_created] = 2
          stats[:places_created] = 3
          stats[:imports_created] = 1
          stats[:exports_created] = 1
          stats[:trips_created] = 2
          stats[:stats_created] = 1
          stats[:notifications_created] = 2
          stats[:visits_created] = 4
          stats[:points_created] = 1000
          stats[:files_restored] = 7
        end
      end

      it 'creates the import directory' do
        expect(FileUtils).to receive(:mkdir_p).with(import_directory)
        service.import
      end

      it 'extracts the archive and processes data' do
        expect(service).to receive(:extract_archive).ordered
        expect(service).to receive(:process_archive_data).ordered
        service.import
      end

      it 'creates a success notification with summary' do
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import completed',
          content: include('1000 points, 4 visits, 3 places, 2 trips'),
          kind: :info
        )
        service.import
      end

      it 'returns import statistics' do
        result = service.import
        expect(result).to include(
          settings_updated: true,
          areas_created: 2,
          places_created: 3,
          imports_created: 1,
          exports_created: 1,
          trips_created: 2,
          stats_created: 1,
          notifications_created: 2,
          visits_created: 4,
          points_created: 1000,
          files_restored: 7
        )
      end
    end

    context 'when an error happens during processing' do
      let(:error_message) { 'boom' }

      before do
        allow(service).to receive(:extract_archive)
        allow(service).to receive(:process_archive_data).and_raise(StandardError, error_message)
        allow(ExceptionReporter).to receive(:call)
      end

      it 'creates a failure notification and re-raises the error' do
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import failed',
          content: "Your data import failed with error: #{error_message}. " \
                   'Please check the archive format and try again.',
          kind: :error
        )

        expect { service.import }.to raise_error(StandardError, error_message)
      end
    end
  end

  describe '#process_archive_data' do
    let(:tmp_dir) { Pathname.new(Dir.mktmpdir) }
    let(:json_path) { tmp_dir.join('data.json') }
    let(:places_calls) { [] }
    let(:visits_batches) { [] }
    let(:points_ingested) { [] }
    let(:points_importer) do
      instance_double(Users::ImportData::Points, add: nil, finalize: 2)
    end

    before do
      payload = {
        'counts' => { 'places' => 2, 'visits' => 2, 'points' => 2 },
        'settings' => { 'theme' => 'dark' },
        'areas' => [],
        'imports' => [],
        'exports' => [],
        'trips' => [],
        'stats' => [],
        'notifications' => [],
        'places' => [
          { 'name' => 'Cafe', 'latitude' => 1.0, 'longitude' => 2.0 },
          { 'name' => 'Library', 'latitude' => 3.0, 'longitude' => 4.0 }
        ],
        'visits' => [
          {
            'name' => 'Morning Coffee',
            'started_at' => '2025-01-01T09:00:00Z',
            'ended_at' => '2025-01-01T10:00:00Z'
          },
          {
            'name' => 'Study Time',
            'started_at' => '2025-01-01T12:00:00Z',
            'ended_at' => '2025-01-01T14:00:00Z'
          }
        ],
        'points' => [
          { 'timestamp' => 1, 'lonlat' => 'POINT(2 1)' },
          { 'timestamp' => 2, 'lonlat' => 'POINT(4 3)' }
        ]
      }

      File.write(json_path, Oj.dump(payload, mode: :compat))

      service.instance_variable_set(:@import_directory, tmp_dir)

      allow(Users::ImportData::Settings).to receive(:new).and_return(double(call: true))
      allow(Users::ImportData::Areas).to receive(:new).and_return(double(call: 0))
      allow(Users::ImportData::Imports).to receive(:new).and_return(double(call: [0, 0]))
      allow(Users::ImportData::Exports).to receive(:new).and_return(double(call: [0, 0]))
      allow(Users::ImportData::Trips).to receive(:new).and_return(double(call: 0))
      allow(Users::ImportData::Stats).to receive(:new).and_return(double(call: 0))
      allow(Users::ImportData::Notifications).to receive(:new).and_return(double(call: 0))

      allow(Users::ImportData::Places).to receive(:new) do |_, batch|
        places_calls << batch
        double(call: batch.size)
      end

      allow(Users::ImportData::Visits).to receive(:new) do |_, batch|
        visits_batches << batch
        double(call: batch.size)
      end

      allow(points_importer).to receive(:add) do |point|
        points_ingested << point
      end

      allow(Users::ImportData::Points).to receive(:new) do |_, points_data, batch_size:|
        expect(points_data).to be_nil
        expect(batch_size).to eq(described_class::STREAM_BATCH_SIZE)
        points_importer
      end
    end

    after do
      FileUtils.remove_entry(tmp_dir)
    end

    it 'streams sections and updates import stats' do
      service.send(:process_archive_data)

      expect(places_calls.flatten.map { |place| place['name'] }).to contain_exactly('Cafe', 'Library')
      expect(visits_batches.flatten.map { |visit| visit['name'] }).to contain_exactly('Morning Coffee', 'Study Time')
      expect(points_ingested.map { |point| point['timestamp'] }).to eq([1, 2])

      stats = service.instance_variable_get(:@import_stats)
      expect(stats[:places_created]).to eq(2)
      expect(stats[:visits_created]).to eq(2)
      expect(stats[:points_created]).to eq(2)
    end
  end
end

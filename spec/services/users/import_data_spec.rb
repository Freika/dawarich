# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData, type: :service do
  let(:user) { create(:user) }
  let(:archive_path) { Rails.root.join('tmp', 'test_export.zip') }
  let(:service) { described_class.new(user, archive_path) }
  let(:import_directory) { Rails.root.join('tmp', "import_#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_1234567890") }

  before do
    allow(Time).to receive(:current).and_return(Time.zone.at(1234567890))
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:rm_rf)
    allow(File).to receive(:directory?).and_return(true)
  end

  describe '#import' do
    let(:sample_data) do
      {
        'counts' => {
          'areas' => 2,
          'places' => 3,
          'imports' => 1,
          'exports' => 1,
          'trips' => 2,
          'stats' => 1,
          'notifications' => 2,
          'visits' => 4,
          'points' => 1000
        },
        'settings' => { 'theme' => 'dark' },
        'areas' => [{ 'name' => 'Home', 'latitude' => '40.7128', 'longitude' => '-74.0060' }],
        'places' => [{ 'name' => 'Office', 'latitude' => '40.7589', 'longitude' => '-73.9851' }],
        'imports' => [{ 'name' => 'test.json', 'source' => 'owntracks' }],
        'exports' => [{ 'name' => 'export.json', 'status' => 'completed' }],
        'trips' => [{ 'name' => 'Trip to NYC', 'distance' => 100.5 }],
        'stats' => [{ 'year' => 2024, 'month' => 1, 'distance' => 456.78 }],
        'notifications' => [{ 'title' => 'Test', 'content' => 'Test notification' }],
        'visits' => [{ 'name' => 'Work Visit', 'duration' => 3600 }],
        'points' => [{ 'latitude' => 40.7128, 'longitude' => -74.0060, 'timestamp' => 1234567890 }]
      }
    end

    before do
      # Mock ZIP file extraction
      zipfile_mock = double('ZipFile')
      allow(zipfile_mock).to receive(:each)
      allow(Zip::File).to receive(:open).with(archive_path).and_yield(zipfile_mock)

      # Mock JSON loading and File operations
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with(import_directory.join('data.json')).and_return(true)
      allow(File).to receive(:read).with(import_directory.join('data.json')).and_return(sample_data.to_json)

      # Mock all import services
      allow(Users::ImportData::Settings).to receive(:new).and_return(double(call: true))
      allow(Users::ImportData::Areas).to receive(:new).and_return(double(call: 2))
      allow(Users::ImportData::Places).to receive(:new).and_return(double(call: 3))
      allow(Users::ImportData::Imports).to receive(:new).and_return(double(call: [1, 5]))
      allow(Users::ImportData::Exports).to receive(:new).and_return(double(call: [1, 2]))
      allow(Users::ImportData::Trips).to receive(:new).and_return(double(call: 2))
      allow(Users::ImportData::Stats).to receive(:new).and_return(double(call: 1))
      allow(Users::ImportData::Notifications).to receive(:new).and_return(double(call: 2))
      allow(Users::ImportData::Visits).to receive(:new).and_return(double(call: 4))
      allow(Users::ImportData::Points).to receive(:new).and_return(double(call: 1000))

      # Mock notifications
      allow(::Notifications::Create).to receive(:new).and_return(double(call: true))

      # Mock cleanup
      allow(service).to receive(:cleanup_temporary_files)
      allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
    end

    context 'when import is successful' do
      it 'creates import directory' do
        expect(FileUtils).to receive(:mkdir_p).with(import_directory)

        service.import
      end

      it 'extracts the archive' do
        expect(Zip::File).to receive(:open).with(archive_path)

        service.import
      end

      it 'loads JSON data from extracted files' do
        expect(File).to receive(:exist?).with(import_directory.join('data.json'))
        expect(File).to receive(:read).with(import_directory.join('data.json'))

        service.import
      end

      it 'calls all import services in correct order' do
        expect(Users::ImportData::Settings).to receive(:new).with(user, sample_data['settings']).ordered
        expect(Users::ImportData::Areas).to receive(:new).with(user, sample_data['areas']).ordered
        expect(Users::ImportData::Places).to receive(:new).with(user, sample_data['places']).ordered
        expect(Users::ImportData::Imports).to receive(:new).with(user, sample_data['imports'], import_directory.join('files')).ordered
        expect(Users::ImportData::Exports).to receive(:new).with(user, sample_data['exports'], import_directory.join('files')).ordered
        expect(Users::ImportData::Trips).to receive(:new).with(user, sample_data['trips']).ordered
        expect(Users::ImportData::Stats).to receive(:new).with(user, sample_data['stats']).ordered
        expect(Users::ImportData::Notifications).to receive(:new).with(user, sample_data['notifications']).ordered
        expect(Users::ImportData::Visits).to receive(:new).with(user, sample_data['visits']).ordered
        expect(Users::ImportData::Points).to receive(:new).with(user, sample_data['points']).ordered

        service.import
      end

      it 'creates success notification with import stats' do
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import completed',
          content: match(/1000 points.*4 visits.*3 places.*2 trips/),
          kind: :info
        )

        service.import
      end

      it 'cleans up temporary files' do
        expect(service).to receive(:cleanup_temporary_files).with(import_directory)

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

      it 'logs expected counts if available' do
        allow(Rails.logger).to receive(:info) # Allow other log messages
        expect(Rails.logger).to receive(:info).with(/Expected entity counts from export:/)

        service.import
      end
    end

    context 'when JSON file is missing' do
      before do
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(import_directory.join('data.json')).and_return(false)
        allow(ExceptionReporter).to receive(:call)
      end

      it 'raises an error' do
        expect { service.import }.to raise_error(StandardError, 'Data file not found in archive: data.json')
      end
    end

    context 'when JSON is invalid' do
      before do
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(import_directory.join('data.json')).and_return(true)
        allow(File).to receive(:read).with(import_directory.join('data.json')).and_return('invalid json')
        allow(ExceptionReporter).to receive(:call)
      end

      it 'raises a JSON parse error' do
        expect { service.import }.to raise_error(StandardError, /Invalid JSON format in data file/)
      end
    end

    context 'when an error occurs during import' do
      let(:error_message) { 'Something went wrong' }

      before do
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(import_directory.join('data.json')).and_return(true)
        allow(File).to receive(:read).with(import_directory.join('data.json')).and_return(sample_data.to_json)
        allow(Users::ImportData::Settings).to receive(:new).and_raise(StandardError, error_message)
        allow(ExceptionReporter).to receive(:call)
        allow(::Notifications::Create).to receive(:new).and_return(double(call: true))
      end

      it 'creates failure notification' do
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import failed',
          content: "Your data import failed with error: #{error_message}. Please check the archive format and try again.",
          kind: :error
        )

        expect { service.import }.to raise_error(StandardError, error_message)
      end

      it 'reports error via ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call).with(
          an_instance_of(StandardError),
          'Data import failed'
        )

        expect { service.import }.to raise_error(StandardError, error_message)
      end

      it 'still cleans up temporary files' do
        expect(service).to receive(:cleanup_temporary_files)

        expect { service.import }.to raise_error(StandardError, error_message)
      end

      it 're-raises the error' do
        expect { service.import }.to raise_error(StandardError, error_message)
      end
    end

    context 'when data sections are missing' do
      let(:minimal_data) { { 'settings' => { 'theme' => 'dark' } } }

      before do
        # Reset JSON file mocking
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(import_directory.join('data.json')).and_return(true)
        allow(File).to receive(:read).with(import_directory.join('data.json')).and_return(minimal_data.to_json)

        # Only expect Settings to be called
        allow(Users::ImportData::Settings).to receive(:new).and_return(double(call: true))
        allow(::Notifications::Create).to receive(:new).and_return(double(call: true))
      end

      it 'only imports available sections' do
        expect(Users::ImportData::Settings).to receive(:new).with(user, minimal_data['settings'])
        expect(Users::ImportData::Areas).not_to receive(:new)
        expect(Users::ImportData::Places).not_to receive(:new)

        service.import
      end
    end
  end

  describe 'private methods' do
    describe '#cleanup_temporary_files' do
      context 'when directory exists' do
        before do
          allow(File).to receive(:directory?).and_return(true)
          allow(Rails.logger).to receive(:info)
        end

        it 'removes the directory' do
          expect(FileUtils).to receive(:rm_rf).with(import_directory)

          service.send(:cleanup_temporary_files, import_directory)
        end

        it 'logs the cleanup' do
          expect(Rails.logger).to receive(:info).with("Cleaning up temporary import directory: #{import_directory}")

          service.send(:cleanup_temporary_files, import_directory)
        end
      end

      context 'when cleanup fails' do
        before do
          allow(File).to receive(:directory?).and_return(true)
          allow(FileUtils).to receive(:rm_rf).and_raise(StandardError, 'Permission denied')
          allow(ExceptionReporter).to receive(:call)
        end

        it 'reports error via ExceptionReporter but does not re-raise' do
          expect(ExceptionReporter).to receive(:call).with(
            an_instance_of(StandardError),
            'Failed to cleanup temporary files'
          )

          expect { service.send(:cleanup_temporary_files, import_directory) }.not_to raise_error
        end
      end

      context 'when directory does not exist' do
        before do
          allow(File).to receive(:directory?).and_return(false)
        end

        it 'does not attempt cleanup' do
          expect(FileUtils).not_to receive(:rm_rf)

          service.send(:cleanup_temporary_files, import_directory)
        end
      end
    end
  end
end

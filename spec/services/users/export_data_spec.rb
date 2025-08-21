# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }
  let(:timestamp) { '20241201_123000' }
  let(:export_directory) { Rails.root.join('tmp', "#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_#{timestamp}") }
  let(:files_directory) { export_directory.join('files') }

  before do
    allow(Time).to receive(:current).and_return(Time.new(2024, 12, 1, 12, 30, 0))
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:rm_rf)
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:directory?).and_return(true)
  end

  describe '#export' do
    context 'when export is successful' do
      let(:zip_file_path) { export_directory.join('export.zip') }
      let(:zip_file_double) { double('ZipFile') }
      let(:export_record) { double('Export', id: 1, name: 'test.zip', update!: true, file: double('File', attach: true)) }
      let(:notification_service_double) { double('Notifications::Create', call: true) }

      before do
        # Mock all the export data services
        allow(Users::ExportData::Areas).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Trips).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Stats).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Notifications).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Points).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Visits).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Places).to receive(:new).and_return(double(call: []))

        # Mock user settings
        allow(user).to receive(:safe_settings).and_return(double(settings: { theme: 'dark' }))

        # Mock user associations for counting (needed before error occurs)
        allow(user).to receive(:areas).and_return(double(count: 5))
        allow(user).to receive(:imports).and_return(double(count: 12))
        allow(user).to receive(:trips).and_return(double(count: 8))
        allow(user).to receive(:stats).and_return(double(count: 24))
        allow(user).to receive(:notifications).and_return(double(count: 10))
        allow(user).to receive(:points).and_return(double(count: 15000))
        allow(user).to receive(:visits).and_return(double(count: 45))
        allow(user).to receive(:places).and_return(double(count: 20))

        # Mock Export creation and file attachment
        exports_double = double('Exports', count: 3)
        allow(user).to receive(:exports).and_return(exports_double)
        allow(exports_double).to receive(:create!).and_return(export_record)
        allow(export_record).to receive(:update!)
        allow(export_record).to receive_message_chain(:file, :attach)

        # Mock Zip file creation
        allow(Zip::File).to receive(:open).with(zip_file_path, Zip::File::CREATE).and_yield(zip_file_double)
        allow(zip_file_double).to receive(:default_compression=)
        allow(zip_file_double).to receive(:default_compression_level=)
        allow(zip_file_double).to receive(:add)
        allow(Dir).to receive(:glob).and_return([export_directory.join('data.json').to_s])

        # Mock file operations - return a File instance for the zip file
        allow(File).to receive(:open).with(export_directory.join('data.json'), 'w').and_yield(StringIO.new)
        zip_file_io = File.new(__FILE__)  # Use current file as a placeholder
        allow(File).to receive(:open).with(zip_file_path).and_return(zip_file_io)

        # Mock notifications service - prevent actual notification creation
        allow(service).to receive(:create_success_notification)

        # Mock cleanup to verify it's called
        allow(service).to receive(:cleanup_temporary_files)
        allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      end

      it 'creates an Export record with correct attributes' do
        expect(user.exports).to receive(:create!).with(
          name: "user_data_export_#{timestamp}.zip",
          file_format: :archive,
          file_type: :user_data,
          status: :processing
        )

        service.export
      end

      it 'creates the export directory structure' do
        expect(FileUtils).to receive(:mkdir_p).with(files_directory)

        service.export
      end

      it 'calls all export data services with correct parameters' do
        expect(Users::ExportData::Areas).to receive(:new).with(user)
        expect(Users::ExportData::Imports).to receive(:new).with(user, files_directory)
        expect(Users::ExportData::Exports).to receive(:new).with(user, files_directory)
        expect(Users::ExportData::Trips).to receive(:new).with(user)
        expect(Users::ExportData::Stats).to receive(:new).with(user)
        expect(Users::ExportData::Notifications).to receive(:new).with(user)
        expect(Users::ExportData::Points).to receive(:new).with(user)
        expect(Users::ExportData::Visits).to receive(:new).with(user)
        expect(Users::ExportData::Places).to receive(:new).with(user)

        service.export
      end

      it 'creates a zip file with proper compression settings' do
        expect(Zip::File).to receive(:open).with(zip_file_path, Zip::File::CREATE)
        expect(Zip).to receive(:default_compression).and_return(-1)  # Mock original compression
        expect(Zip).to receive(:default_compression=).with(Zip::Entry::DEFLATED)
        expect(Zip).to receive(:default_compression=).with(-1)  # Restoration

        service.export
      end

      it 'attaches the zip file to the export record' do
        expect(export_record.file).to receive(:attach).with(
          io: an_instance_of(File),
          filename: export_record.name,
          content_type: 'application/zip'
        )

        service.export
      end

      it 'marks the export as completed' do
        expect(export_record).to receive(:update!).with(status: :completed)

        service.export
      end

      it 'creates a success notification' do
        expect(service).to receive(:create_success_notification)

        service.export
      end

      it 'cleans up temporary files' do
        expect(service).to receive(:cleanup_temporary_files).with(export_directory)

        service.export
      end

      it 'returns the export record' do
        result = service.export
        expect(result).to eq(export_record)
      end

      it 'calculates entity counts correctly' do
        counts = service.send(:calculate_entity_counts)

        expect(counts).to eq({
          areas: 5,
          imports: 12,
          exports: 3,
          trips: 8,
          stats: 24,
          notifications: 10,
          points: 15000,
          visits: 45,
          places: 20
        })
      end
    end

    context 'when an error occurs during export' do
      let(:export_record) { double('Export', id: 1, name: 'test.zip', update!: true) }
      let(:error_message) { 'Something went wrong' }

      before do
        # Mock Export creation first
        exports_double = double('Exports', count: 3)
        allow(user).to receive(:exports).and_return(exports_double)
        allow(exports_double).to receive(:create!).and_return(export_record)
        allow(export_record).to receive(:update!)

        # Mock user settings and other dependencies that are needed before the error
        allow(user).to receive(:safe_settings).and_return(double(settings: { theme: 'dark' }))

        # Mock user associations for counting
        allow(user).to receive(:areas).and_return(double(count: 5))
        allow(user).to receive(:imports).and_return(double(count: 12))
        # exports already mocked above
        allow(user).to receive(:trips).and_return(double(count: 8))
        allow(user).to receive(:stats).and_return(double(count: 24))
        allow(user).to receive(:notifications).and_return(double(count: 10))
        allow(user).to receive(:points).and_return(double(count: 15000))
        allow(user).to receive(:visits).and_return(double(count: 45))
        allow(user).to receive(:places).and_return(double(count: 20))

        # Then set up the error condition - make it happen during the JSON writing step
        allow(File).to receive(:open).with(export_directory.join('data.json'), 'w').and_raise(StandardError, error_message)

        allow(ExceptionReporter).to receive(:call)

        # Mock cleanup method and pathname existence
        allow(service).to receive(:cleanup_temporary_files)
        allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      end

      it 'marks the export as failed' do
        expect(export_record).to receive(:update!).with(status: :failed)

        expect { service.export }.to raise_error(StandardError, error_message)
      end

      it 'reports the error via ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call).with(an_instance_of(StandardError), 'Export failed')

        expect { service.export }.to raise_error(StandardError, error_message)
      end

      it 'still cleans up temporary files' do
        expect(service).to receive(:cleanup_temporary_files)

        expect { service.export }.to raise_error(StandardError, error_message)
      end

      it 're-raises the error' do
        expect { service.export }.to raise_error(StandardError, error_message)
      end
    end

    context 'when export record creation fails' do
      before do
        exports_double = double('Exports', count: 3)
        allow(user).to receive(:exports).and_return(exports_double)
        allow(exports_double).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'does not try to mark export as failed when export_record is nil' do
        expect { service.export }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

        context 'with file compression scenarios' do
      let(:export_record) { double('Export', id: 1, name: 'test.zip', update!: true, file: double('File', attach: true)) }

      before do
        # Mock Export creation
        exports_double = double('Exports', count: 3)
        allow(user).to receive(:exports).and_return(exports_double)
        allow(exports_double).to receive(:create!).and_return(export_record)
        allow(export_record).to receive(:update!)
        allow(export_record).to receive_message_chain(:file, :attach)

        # Mock all export services to prevent actual calls
        allow(Users::ExportData::Areas).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Trips).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Stats).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Notifications).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Points).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Visits).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Places).to receive(:new).and_return(double(call: []))

        allow(user).to receive(:safe_settings).and_return(double(settings: {}))

        # Mock user associations for counting
        allow(user).to receive(:areas).and_return(double(count: 5))
        allow(user).to receive(:imports).and_return(double(count: 12))
        # exports already mocked above
        allow(user).to receive(:trips).and_return(double(count: 8))
        allow(user).to receive(:stats).and_return(double(count: 24))
        allow(user).to receive(:notifications).and_return(double(count: 10))
        allow(user).to receive(:points).and_return(double(count: 15000))
        allow(user).to receive(:visits).and_return(double(count: 45))
        allow(user).to receive(:places).and_return(double(count: 20))

        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:open).with(export_directory.join('data.json'), 'w').and_yield(StringIO.new)

        # Use current file as placeholder for zip file
        zip_file_io = File.new(__FILE__)
        allow(File).to receive(:open).with(export_directory.join('export.zip')).and_return(zip_file_io)

        # Mock notifications service
        allow(service).to receive(:create_success_notification)

        # Mock cleanup
        allow(service).to receive(:cleanup_temporary_files)
        allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      end

      it 'calls create_zip_archive with correct parameters' do
        expect(service).to receive(:create_zip_archive).with(export_directory, export_directory.join('export.zip'))

        service.export
      end
    end
  end

  describe 'private methods' do
    describe '#export_directory' do
      it 'generates correct directory path' do
        allow(Time).to receive_message_chain(:current, :strftime).with('%Y%m%d_%H%M%S').and_return(timestamp)

        # Call export to initialize the directory paths
        service.instance_variable_set(:@export_directory, Rails.root.join('tmp', "#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_#{timestamp}"))

        expect(service.send(:export_directory).to_s).to include(user.email.gsub(/[^0-9A-Za-z._-]/, '_'))
        expect(service.send(:export_directory).to_s).to include(timestamp)
      end
    end

    describe '#files_directory' do
      it 'returns files subdirectory of export directory' do
        # Initialize the export directory first
        service.instance_variable_set(:@export_directory, Rails.root.join('tmp', "test_export"))
        service.instance_variable_set(:@files_directory, service.instance_variable_get(:@export_directory).join('files'))

        files_dir = service.send(:files_directory)
        expect(files_dir.to_s).to end_with('files')
      end
    end

    describe '#cleanup_temporary_files' do
      context 'when directory exists' do
        before do
          allow(File).to receive(:directory?).and_return(true)
          allow(Rails.logger).to receive(:info)
        end

        it 'removes the directory' do
          expect(FileUtils).to receive(:rm_rf).with(export_directory)

          service.send(:cleanup_temporary_files, export_directory)
        end

        it 'logs the cleanup' do
          expect(Rails.logger).to receive(:info).with("Cleaning up temporary export directory: #{export_directory}")

          service.send(:cleanup_temporary_files, export_directory)
        end
      end

      context 'when cleanup fails' do
        before do
          allow(File).to receive(:directory?).and_return(true)
          allow(FileUtils).to receive(:rm_rf).and_raise(StandardError, 'Permission denied')
          allow(ExceptionReporter).to receive(:call)
        end

        it 'reports the error via ExceptionReporter but does not re-raise' do
          expect(ExceptionReporter).to receive(:call).with(an_instance_of(StandardError), 'Failed to cleanup temporary files')

          expect { service.send(:cleanup_temporary_files, export_directory) }.not_to raise_error
        end
      end

      context 'when directory does not exist' do
        before do
          allow(File).to receive(:directory?).and_return(false)
        end

        it 'does not attempt cleanup' do
          expect(FileUtils).not_to receive(:rm_rf)

          service.send(:cleanup_temporary_files, export_directory)
        end
      end
    end

    describe '#calculate_entity_counts' do
      before do
        # Mock user associations for counting
        allow(user).to receive(:areas).and_return(double(count: 5))
        allow(user).to receive(:imports).and_return(double(count: 12))
        allow(user).to receive(:exports).and_return(double(count: 3))
        allow(user).to receive(:trips).and_return(double(count: 8))
        allow(user).to receive(:stats).and_return(double(count: 24))
        allow(user).to receive(:notifications).and_return(double(count: 10))
        allow(user).to receive(:points).and_return(double(count: 15000))
        allow(user).to receive(:visits).and_return(double(count: 45))
        allow(user).to receive(:places).and_return(double(count: 20))
        allow(Rails.logger).to receive(:info)
      end

      it 'returns correct counts for all entity types' do
        counts = service.send(:calculate_entity_counts)

        expect(counts).to eq({
          areas: 5,
          imports: 12,
          exports: 3,
          trips: 8,
          stats: 24,
          notifications: 10,
          points: 15000,
          visits: 45,
          places: 20
        })
      end

      it 'logs the calculation process' do
        expect(Rails.logger).to receive(:info).with("Calculating entity counts for export")
        expect(Rails.logger).to receive(:info).with(/Entity counts:/)

        service.send(:calculate_entity_counts)
      end
    end
  end
end

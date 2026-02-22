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
  end

  describe '#export' do
    context 'when export is successful' do
      before do
        # Mock export services that need file directories to return empty arrays
        allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))

        # Mock notifications service
        allow(Notifications::Create).to receive(:new).and_return(double(call: true))
      end

      after do
        # Cleanup test files
        FileUtils.rm_rf(export_directory) if File.directory?(export_directory)
      end

      it 'creates an Export record with correct attributes' do
        result = service.export

        expect(result).to be_a(Export)
        expect(result.name).to eq("user_data_export_#{timestamp}.zip")
        expect(result.file_format).to eq('archive')
        expect(result.file_type).to eq('user_data')
        expect(result.status).to eq('completed')
      end

      it 'creates a manifest.json file in the archive' do
        result = service.export

        # Download and extract the archive to check contents
        temp_dir = Rails.root.join('tmp/test_extract')
        FileUtils.mkdir_p(temp_dir)

        begin
          archive_content = result.file.download
          temp_zip = temp_dir.join('test.zip')
          File.binwrite(temp_zip, archive_content)

          Zip::File.open(temp_zip) do |zip_file|
            manifest_entry = zip_file.find_entry('manifest.json')
            expect(manifest_entry).not_to be_nil

            manifest = JSON.parse(manifest_entry.get_input_stream.read)
            expect(manifest['format_version']).to eq(2)
            expect(manifest['counts']).to be_a(Hash)
            expect(manifest['files']).to be_a(Hash)
            expect(manifest['files']['points']).to be_an(Array)
            expect(manifest['files']['visits']).to be_an(Array)
            expect(manifest['files']['stats']).to be_an(Array)
            expect(manifest['files']['tracks']).to be_an(Array)
            expect(manifest['files']['digests']).to be_an(Array)
          end
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      it 'creates JSONL files in the archive' do
        result = service.export

        temp_dir = Rails.root.join('tmp/test_extract')
        FileUtils.mkdir_p(temp_dir)

        begin
          archive_content = result.file.download
          temp_zip = temp_dir.join('test.zip')
          File.binwrite(temp_zip, archive_content)

          Zip::File.open(temp_zip) do |zip_file|
            expect(zip_file.find_entry('settings.jsonl')).not_to be_nil
            expect(zip_file.find_entry('areas.jsonl')).not_to be_nil
            expect(zip_file.find_entry('places.jsonl')).not_to be_nil
            expect(zip_file.find_entry('trips.jsonl')).not_to be_nil
            expect(zip_file.find_entry('notifications.jsonl')).not_to be_nil
            expect(zip_file.find_entry('imports.jsonl')).not_to be_nil
            expect(zip_file.find_entry('exports.jsonl')).not_to be_nil
            expect(zip_file.find_entry('tags.jsonl')).not_to be_nil
            expect(zip_file.find_entry('taggings.jsonl')).not_to be_nil
            expect(zip_file.find_entry('raw_data_archives.jsonl')).not_to be_nil
          end
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      it 'marks the export as completed' do
        result = service.export

        expect(result.status).to eq('completed')
      end

      it 'creates a success notification' do
        expect(Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Export completed',
          content: /Your data export has been processed successfully/,
          kind: :info
        ).and_return(double(call: true))

        service.export
      end

      it 'returns the export record' do
        result = service.export

        expect(result).to be_a(Export)
        expect(result.user).to eq(user)
      end

      it 'attaches the zip file to the export record' do
        result = service.export

        expect(result.file).to be_attached
        expect(result.file.content_type).to eq('application/zip')
      end

      it 'has correct format version constant' do
        expect(Users::ExportData::FORMAT_VERSION).to eq(2)
      end
    end

    context 'when an error occurs during export' do
      let(:error_message) { 'Something went wrong during export' }

      before do
        # Mock export services that need file directories
        allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
        allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))

        # Make the write_manifest method fail to simulate an error after export record is created
        allow(service).to receive(:write_manifest).and_raise(StandardError, error_message)
        allow(ExceptionReporter).to receive(:call)
      end

      after do
        FileUtils.rm_rf(export_directory) if File.directory?(export_directory)
      end

      it 'marks the export as failed' do
        expect { service.export }.to raise_error(StandardError, error_message)

        export_record = user.exports.last
        expect(export_record).not_to be_nil
        expect(export_record.status).to eq('failed')
      end

      it 'reports the error via ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call).with(an_instance_of(StandardError), 'Export failed')

        expect { service.export }.to raise_error(StandardError, error_message)
      end

      it 're-raises the error' do
        expect { service.export }.to raise_error(StandardError, error_message)
      end
    end

    context 'when export record creation fails' do
      before do
        allow(user).to receive_message_chain(:exports, :create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'raises the error without marking export as failed' do
        expect { service.export }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe 'private methods' do
    describe '#calculate_entity_counts' do
      before do
        allow(Rails.logger).to receive(:info)
      end

      it 'returns correct counts for all entity types' do
        # Create some test data
        create_list(:area, 2, user: user)
        create(:import, user: user)
        create(:trip, user: user)
        create(:stat, user: user)
        create(:notification, user: user)
        create(:point, user: user)

        counts = service.send(:calculate_entity_counts)

        expect(counts[:areas]).to eq(2)
        expect(counts[:imports]).to eq(1)
        expect(counts[:trips]).to eq(1)
        expect(counts[:stats]).to eq(1)
        expect(counts[:notifications]).to eq(1)
        expect(counts[:points]).to eq(1)
      end

      it 'logs the calculation process' do
        expect(Rails.logger).to receive(:info).with('Calculating entity counts for export')
        expect(Rails.logger).to receive(:info).with(/Entity counts:/)

        service.send(:calculate_entity_counts)
      end
    end

    describe '#cleanup_temporary_files' do
      context 'when directory exists' do
        let(:temp_dir) { Rails.root.join('tmp/test_cleanup') }

        before do
          FileUtils.mkdir_p(temp_dir)
          allow(Rails.logger).to receive(:info)
        end

        after do
          FileUtils.rm_rf(temp_dir) if File.directory?(temp_dir)
        end

        it 'removes the directory' do
          service.send(:cleanup_temporary_files, temp_dir)

          expect(File.directory?(temp_dir)).to be false
        end

        it 'logs the cleanup' do
          expect(Rails.logger).to receive(:info).with("Cleaning up temporary export directory: #{temp_dir}")

          service.send(:cleanup_temporary_files, temp_dir)
        end
      end

      context 'when cleanup fails' do
        before do
          allow(File).to receive(:directory?).and_return(true)
          allow(FileUtils).to receive(:rm_rf).and_raise(StandardError, 'Permission denied')
          allow(ExceptionReporter).to receive(:call)
        end

        it 'reports the error via ExceptionReporter but does not re-raise' do
          expect(ExceptionReporter).to receive(:call).with(an_instance_of(StandardError),
                                                           'Failed to cleanup temporary files')

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

    describe '#dawarich_version' do
      it 'returns APP_VERSION if defined' do
        stub_const('APP_VERSION', '1.2.3')
        expect(service.send(:dawarich_version)).to eq('1.2.3')
      end

      it 'returns unknown if APP_VERSION is not defined' do
        hide_const('APP_VERSION')
        expect(service.send(:dawarich_version)).to eq('unknown')
      end
    end
  end
end

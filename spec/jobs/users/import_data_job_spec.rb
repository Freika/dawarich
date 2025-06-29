# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportDataJob, type: :job do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :user_data_archive, name: 'test_export.zip') }
  let(:archive_path) { Rails.root.join('tmp', 'test_export.zip') }
  let(:job) { described_class.new }

  before do
    # Create a mock ZIP file
    FileUtils.touch(archive_path)

    # Mock the import file attachment
    allow(import).to receive(:file).and_return(
      double('ActiveStorage::Attached::One',
        download: proc { |&block|
          File.read(archive_path).each_char { |c| block.call(c) }
        }
      )
    )
  end

  after do
    FileUtils.rm_f(archive_path) if File.exist?(archive_path)
  end

  describe '#perform' do
    context 'when import is successful' do
      before do
        # Mock the import service
        import_service = instance_double(Users::ImportData)
        allow(Users::ImportData).to receive(:new).and_return(import_service)
        allow(import_service).to receive(:import).and_return({
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
        })

        # Mock file operations
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)
        allow(Rails.logger).to receive(:info)
      end

      it 'calls the import service with correct parameters' do
        expect(Users::ImportData).to receive(:new).with(user, anything)

        job.perform(import.id)
      end

      it 'calls import on the service' do
        import_service = instance_double(Users::ImportData)
        allow(Users::ImportData).to receive(:new).and_return(import_service)
        expect(import_service).to receive(:import)

        job.perform(import.id)
      end

      it 'completes successfully without updating import status' do
        expect(import).not_to receive(:update!)

        job.perform(import.id)
      end

      it 'does not create error notifications when successful' do
        expect(::Notifications::Create).not_to receive(:new)

        job.perform(import.id)
      end
    end

    context 'when import fails' do
      let(:error_message) { 'Import failed due to invalid archive' }
      let(:error) { StandardError.new(error_message) }

      before do
        # Mock the import service to raise an error
        import_service = instance_double(Users::ImportData)
        allow(Users::ImportData).to receive(:new).and_return(import_service)
        allow(import_service).to receive(:import).and_raise(error)

        # Mock notification creation
        notification_service = instance_double(::Notifications::Create, call: true)
        allow(::Notifications::Create).to receive(:new).and_return(notification_service)

        # Mock file operations
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:delete)
        allow(Rails.logger).to receive(:info)

        # Mock ExceptionReporter
        allow(ExceptionReporter).to receive(:call)
      end

      it 'reports the error to ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call).with(error, "Import job failed for user #{user.id}")

        expect { job.perform(import.id) }.to raise_error(StandardError, error_message)
      end

      it 'does not update import status on failure' do
        expect(import).not_to receive(:update!)

        expect { job.perform(import.id) }.to raise_error(StandardError, error_message)
      end

      it 'creates a failure notification for the user' do
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import failed',
          content: "Your data import failed with error: #{error_message}. Please check the archive format and try again.",
          kind: :error
        )

        expect { job.perform(import.id) }.to raise_error(StandardError, error_message)
      end

      it 're-raises the error' do
        expect { job.perform(import.id) }.to raise_error(StandardError, error_message)
      end
    end

    context 'when import does not exist' do
      let(:non_existent_import_id) { 999999 }

      it 'raises ActiveRecord::RecordNotFound' do
        expect { job.perform(non_existent_import_id) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'does not create a notification when import is not found' do
        expect(::Notifications::Create).not_to receive(:new)

        expect { job.perform(non_existent_import_id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when archive file download fails' do
      let(:error_message) { 'File download error' }
      let(:error) { StandardError.new(error_message) }

      before do
        # Mock file download to fail
        allow(import).to receive(:file).and_return(
          double('ActiveStorage::Attached::One', download: proc { raise error })
        )

        # Mock notification creation
        notification_service = instance_double(::Notifications::Create, call: true)
        allow(::Notifications::Create).to receive(:new).and_return(notification_service)
      end

      it 'creates notification with the correct user object' do
        notification_service = instance_double(::Notifications::Create, call: true)
        expect(::Notifications::Create).to receive(:new).with(
          user: user,
          title: 'Data import failed',
          content: a_string_matching(/Your data import failed with error:.*Please check the archive format and try again\./),
          kind: :error
        ).and_return(notification_service)

        expect(notification_service).to receive(:call)

        expect { job.perform(import.id) }.to raise_error(StandardError)
      end
    end
  end

  describe 'job configuration' do
    it 'is queued in the imports queue' do
      expect(described_class.queue_name).to eq('imports')
    end
  end
end

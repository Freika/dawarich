# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Notifications, type: :service do
  let(:user) { create(:user) }
  let(:notifications_data) do
    [
      {
        'kind' => 'info',
        'title' => 'Import completed',
        'content' => 'Your data import has been processed successfully',
        'read_at' => '2024-01-01T12:30:00Z',
        'created_at' => '2024-01-01T12:00:00Z',
        'updated_at' => '2024-01-01T12:30:00Z'
      },
      {
        'kind' => 'error',
        'title' => 'Import failed',
        'content' => 'There was an error processing your data',
        'read_at' => nil,
        'created_at' => '2024-01-02T10:00:00Z',
        'updated_at' => '2024-01-02T10:00:00Z'
      }
    ]
  end
  let(:service) { described_class.new(user, notifications_data) }

  describe '#call' do
    context 'with valid notifications data' do
      it 'creates new notifications for the user' do
        expect { service.call }.to change { user.notifications.count }.by(2)
      end

      it 'creates notifications with correct attributes' do
        service.call

        import_notification = user.notifications.find_by(title: 'Import completed')
        expect(import_notification).to have_attributes(
          kind: 'info',
          title: 'Import completed',
          content: 'Your data import has been processed successfully',
          read_at: Time.parse('2024-01-01T12:30:00Z')
        )

        error_notification = user.notifications.find_by(title: 'Import failed')
        expect(error_notification).to have_attributes(
          kind: 'error',
          title: 'Import failed',
          content: 'There was an error processing your data',
          read_at: nil
        )
      end

      it 'returns the number of notifications created' do
        result = service.call
        expect(result).to eq(2)
      end

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing 2 notifications for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with('Notifications import completed. Created: 2')

        service.call
      end
    end

    context 'with duplicate notifications' do
      before do
        # Create an existing notification with same title, content, and created_at
        user.notifications.create!(
          kind: 'info',
          title: 'Import completed',
          content: 'Your data import has been processed successfully',
          created_at: Time.parse('2024-01-01T12:00:00Z')
        )
      end

      it 'skips duplicate notifications' do
        expect { service.call }.to change { user.notifications.count }.by(1)
      end

      it 'logs when skipping duplicates' do
        allow(Rails.logger).to receive(:debug) # Allow any debug logs
        expect(Rails.logger).to receive(:debug).with('Notification already exists: Import completed')

        service.call
      end

      it 'returns only the count of newly created notifications' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with invalid notification data' do
      let(:notifications_data) do
        [
          { 'kind' => 'info', 'title' => 'Valid Notification', 'content' => 'Valid content' },
          'invalid_data',
          { 'kind' => 'error', 'title' => 'Another Valid Notification', 'content' => 'Another valid content' }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { user.notifications.count }.by(2)
      end

      it 'returns the count of valid notifications created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with validation errors' do
      let(:notifications_data) do
        [
          { 'kind' => 'info', 'title' => 'Valid Notification', 'content' => 'Valid content' },
          { 'kind' => 'info', 'content' => 'Missing title' }, # missing title
          { 'kind' => 'error', 'title' => 'Missing content' } # missing content
        ]
      end

      it 'only creates valid notifications' do
        expect { service.call }.to change { user.notifications.count }.by(1)
      end

      it 'logs validation errors' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        service.call
      end
    end

    context 'with nil notifications data' do
      let(:notifications_data) { nil }

      it 'does not create any notifications' do
        expect { service.call }.not_to(change { user.notifications.count })
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array notifications data' do
      let(:notifications_data) { 'invalid_data' }

      it 'does not create any notifications' do
        expect { service.call }.not_to(change { user.notifications.count })
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty notifications data' do
      let(:notifications_data) { [] }

      it 'does not create any notifications' do
        expect { service.call }.not_to(change { user.notifications.count })
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 notifications for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with('Notifications import completed. Created: 0')

        service.call
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end
